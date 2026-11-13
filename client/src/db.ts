import { openDB, type DBSchema } from 'idb';
import type { Category, CategoryStats, Item, ItemInput } from './api';

/**
 * Everything lives on this device in IndexedDB: items, and photos as Blobs keyed by id.
 * An item's image_url is either "img:<id>" (a photo stored here) or a remote https URL.
 */
interface TackleDB extends DBSchema {
  items: { key: number; value: Item; indexes: { upc: string } };
  images: { key: string; value: Blob };
}

const CATEGORY_IDS: Category[] = ['soft_plastic', 'hard_bait', 'terminal', 'line', 'rod', 'reel', 'other'];

const dbPromise = openDB<TackleDB>('tackletracker', 1, {
  upgrade(db) {
    const items = db.createObjectStore('items', { keyPath: 'id', autoIncrement: true });
    items.createIndex('upc', 'upc');
    db.createObjectStore('images');
  },
});

/** UPC-A (12), EAN-13 and GTIN-14 of the same product differ only by leading zeros. */
export function normalizeUpc(code: unknown) {
  const digits = String(code ?? '').replace(/\D/g, '').replace(/^0+/, '');
  return digits || null;
}

function clean(input: Partial<ItemInput>): Partial<ItemInput> {
  const out: Record<string, unknown> = {};
  for (const [k, raw] of Object.entries(input)) {
    let v: unknown = typeof raw === 'string' ? raw.trim() : raw;
    if (v === '') v = null;
    if (k === 'upc') v = normalizeUpc(v);
    if (k === 'quantity' || k === 'min_quantity') v = Math.max(0, parseInt(String(v), 10) || 0);
    if (k === 'price') v = v == null ? null : Number(v) || null;
    if (k === 'on_list') v = !!v;
    if (k === 'specs') v = v && typeof v === 'object' ? v : {};
    if (k === 'category' && !CATEGORY_IDS.includes(v as Category)) v = 'other';
    out[k] = v;
  }
  return out as Partial<ItemInput>;
}

const DEFAULTS: Omit<ItemInput, 'name'> = {
  brand: null, category: 'other', type: null, color: null, size: null, quantity: 0, unit: 'pack', min_quantity: 0,
  location: null, upc: null, sku: null, price: null, image_url: null, product_url: null, specs: {}, notes: null, on_list: false,
};

const collator = new Intl.Collator(undefined, { sensitivity: 'base', numeric: true });
const byShelfOrder = (a: Item, b: Item) =>
  CATEGORY_IDS.indexOf(a.category) - CATEGORY_IDS.indexOf(b.category) ||
  collator.compare(a.brand ?? '', b.brand ?? '') ||
  collator.compare(a.name, b.name) ||
  collator.compare(a.color ?? '', b.color ?? '');

export const isLow = (it: Item) => it.min_quantity > 0 && it.quantity <= it.min_quantity;

export async function listItems({ low = false } = {}) {
  const all = await (await dbPromise).getAll('items');
  return all.filter((it) => !low || isLow(it) || it.on_list).sort(byShelfOrder);
}

export async function getItem(id: number) {
  const item = await (await dbPromise).get('items', id);
  if (!item) throw new Error('That item no longer exists');
  return item;
}

export async function findByUpc(code: string) {
  const upc = normalizeUpc(code);
  return upc ? (await dbPromise).getAllFromIndex('items', 'upc', upc) : [];
}

export async function createItem(input: Partial<ItemInput>) {
  const data = clean(input);
  if (!data.name) throw new Error('Name is required');
  const now = new Date().toISOString();
  const db = await dbPromise;
  // id is assigned by the store; the cast covers the property it fills in.
  const id = await db.add('items', { ...DEFAULTS, ...data, created_at: now, updated_at: now } as Item);
  return getItem(id);
}

export async function updateItem(id: number, input: Partial<ItemInput>) {
  const data = clean(input);
  if ('name' in data && !data.name) throw new Error('Name is required');
  const db = await dbPromise;
  const tx = db.transaction('items', 'readwrite');
  const current = await tx.store.get(id);
  if (!current) throw new Error('That item no longer exists');
  const { id: _id, created_at: _c, updated_at: _u, ...rest } = data as Partial<Item>;
  const next = { ...current, ...rest, updated_at: new Date().toISOString() };
  await tx.store.put(next);
  await tx.done;
  if (current.image_url !== next.image_url) await dropUnusedImage(current.image_url);
  return next;
}

export async function adjustQuantity(id: number, delta: number) {
  const db = await dbPromise;
  const tx = db.transaction('items', 'readwrite');
  const item = await tx.store.get(id);
  if (!item) throw new Error('That item no longer exists');
  item.quantity = Math.max(0, item.quantity + delta);
  item.updated_at = new Date().toISOString();
  await tx.store.put(item);
  await tx.done;
  return item;
}

export async function deleteItem(id: number) {
  const db = await dbPromise;
  const item = await db.get('items', id);
  await db.delete('items', id);
  if (item) await dropUnusedImage(item.image_url);
}

/** Items can share a photo, so only delete one nothing else points at. */
async function dropUnusedImage(ref: string | null) {
  if (!ref?.startsWith('img:')) return;
  const db = await dbPromise;
  const tx = db.transaction(['items', 'images'], 'readwrite');
  const stillUsed = (await tx.objectStore('items').getAll()).some((it) => it.image_url === ref);
  if (!stillUsed) await tx.objectStore('images').delete(ref.slice(4));
  await tx.done;
  objectUrls.delete(ref);
}

export async function stats(): Promise<CategoryStats[]> {
  const by = new Map<Category, CategoryStats>();
  for (const it of await listItems()) {
    const s = by.get(it.category) ?? { category: it.category, items: 0, units: 0, low: 0, value: 0 };
    s.items++;
    s.units += it.quantity;
    s.low += isLow(it) || it.on_list ? 1 : 0;
    s.value += it.quantity * (it.price ?? 0);
    by.set(it.category, s);
  }
  return CATEGORY_IDS.filter((c) => by.has(c)).map((c) => by.get(c)!);
}

// ---- Photos ----

export async function saveImage(blob: Blob) {
  const id = crypto.randomUUID();
  await (await dbPromise).put('images', blob, id);
  return `img:${id}`;
}

const objectUrls = new Map<string, Promise<string | null>>();

/** Turns an item's image_url into something an <img> can show. */
export function imageSrc(ref: string | null): Promise<string | null> | string | null {
  if (!ref?.startsWith('img:')) return ref;
  let url = objectUrls.get(ref);
  if (!url) {
    url = dbPromise.then((db) => db.get('images', ref.slice(4))).then((b) => (b ? URL.createObjectURL(b) : null));
    objectUrls.set(ref, url);
  }
  return url;
}

// ---- Backup / restore ----

export interface Backup {
  app: 'TackleTracker';
  version: 1;
  exported_at: string;
  items: Item[];
  /** Photos stored on the device, as data: URLs keyed by image id. */
  images: Record<string, string>;
}

const blobToDataUrl = (b: Blob) => new Promise<string>((resolve, reject) => {
  const r = new FileReader();
  r.onload = () => resolve(r.result as string);
  r.onerror = () => reject(r.error);
  r.readAsDataURL(b);
});

export async function exportBackup(): Promise<Backup> {
  const db = await dbPromise;
  const items = await listItems();
  const images: Record<string, string> = {};
  for (const it of items) {
    const id = it.image_url?.startsWith('img:') ? it.image_url.slice(4) : null;
    if (!id || images[id]) continue;
    const blob = await db.get('images', id);
    if (blob) images[id] = await blobToDataUrl(blob);
  }
  return { app: 'TackleTracker', version: 1, exported_at: new Date().toISOString(), items, images };
}

export async function importBackup(data: unknown, { replace = false } = {}) {
  const backup = data as Partial<Backup>;
  if (backup?.app !== 'TackleTracker' || !Array.isArray(backup.items)) throw new Error("That file isn't a TackleTracker backup");

  // Decode photos before opening the transaction; IndexedDB transactions close on any other await.
  const blobs = new Map<string, Blob>();
  for (const [id, dataUrl] of Object.entries(backup.images ?? {})) {
    blobs.set(id, await (await fetch(dataUrl)).blob());
  }

  const db = await dbPromise;
  const tx = db.transaction(['items', 'images'], 'readwrite');
  if (replace) {
    await tx.objectStore('items').clear();
    await tx.objectStore('images').clear();
  }
  for (const [id, blob] of blobs) await tx.objectStore('images').put(blob, id);
  const now = new Date().toISOString();
  for (const raw of backup.items as Partial<Item>[]) {
    const { id: _id, ...rest } = raw;
    const data = clean(rest);
    if (!data.name) continue;
    // A photo missing from the file would show as a broken image once the old ones are cleared.
    let image = data.image_url ?? null;
    if (image?.startsWith('img:') && !blobs.has(image.slice(4)) && replace) image = null;
    await tx.objectStore('items').add({
      ...DEFAULTS, ...data, image_url: image,
      created_at: raw.created_at ?? now, updated_at: raw.updated_at ?? now,
    } as Item);
  }
  await tx.done;
  return backup.items.length;
}

/** Ask the browser not to clear our storage under pressure (granted automatically for home-screen apps on most phones). */
export async function requestPersistence() {
  try {
    return (await navigator.storage?.persist?.()) ?? false;
  } catch {
    return false;
  }
}
