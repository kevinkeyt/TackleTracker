import type { Category, TwProduct, TwVariant, UpcSuggestion } from './api';
import { normalizeUpc, saveImage } from './db';

const TW_HOST = 'www.tacklewarehouse.com';

export function twSearchUrl(text: string) {
  return `https://${TW_HOST}/search-tackle.html?searchtext=${encodeURIComponent(text)}`;
}

/** Best guess at our category from a product title. The user can always change it. */
export function guessCategory(title = ''): Category {
  const t = title.toLowerCase();
  if (/\breel\b/.test(t)) return 'reel';
  if (/\brod\b|casting rod|spinning rod/.test(t)) return 'rod';
  if (/\bline\b|fluorocarbon|monofilament|\bbraid/.test(t)) return 'line';
  if (/\bhooks?\b|weights?\b|sinker|\bjig head|swivel|split ring|snap|bobber|bead|peg/.test(t)) return 'terminal';
  if (/crank|jerkbait|topwater|popper|walking|spinnerbait|chatter|bladed|buzzbait|swimbait|glide|lipless|spoon|frog|jig\b|underspin|wakebait|prop/.test(t)) {
    // Soft swimbaits and frogs come in packs too, but hard bodies are the common case.
    if (/soft|paddle ?tail|\d+\s*pk\b/.test(t)) return 'soft_plastic';
    return 'hard_bait';
  }
  if (/worm|craw|creature|grub|tube|stick ?bait|senko|minnow|shad|fluke|trailer|beaver|\d+\s*pk\b|soft/.test(t)) return 'soft_plastic';
  return 'other';
}

function withWidth(imgUrl: string, width: number) {
  try {
    const u = new URL(imgUrl, `https://${TW_HOST}/`);
    if (u.searchParams.has('path')) u.searchParams.set('nw', String(width));
    return u.toString();
  } catch {
    return imgUrl;
  }
}

function largestFromSrcset(srcset: string | null) {
  if (!srcset) return null;
  const best = srcset.split(',').map((s) => s.trim().split(/\s+/)).map(([u, w]) => [u, parseInt(w, 10) || 0] as const)
    .sort((a, b) => b[1] - a[1])[0];
  return best ? withWidth(best[0], 600) : null;
}

/**
 * Reads a Tackle Warehouse product page (…/descpage-XXXX.html) straight from the phone. Each color/size
 * is a schema.org Offer row carrying its own SKU, price, GTIN and swatch image.
 */
export async function fetchTwProduct(rawUrl: string): Promise<TwProduct> {
  let url: URL;
  try {
    url = new URL(rawUrl.trim());
  } catch {
    throw new Error('That is not a valid link');
  }
  if (!/(^|\.)tacklewarehouse\.com$/.test(url.hostname) || !/descpage-/i.test(url.pathname)) {
    throw new Error('Paste a Tackle Warehouse product page link (it contains "descpage-")');
  }
  url.protocol = 'https:';
  url.hostname = TW_HOST;
  url.hash = '';

  let res: Response;
  try {
    res = await fetch(url, { credentials: 'omit' });
  } catch {
    throw new Error("Couldn't reach Tackle Warehouse. Check your connection and try again.");
  }
  if (!res.ok) throw new Error(`Tackle Warehouse returned ${res.status}`);
  const doc = new DOMParser().parseFromString(await res.text(), 'text/html');
  const attr = (el: Element | null | undefined, name: string) => el?.getAttribute(name) ?? null;
  const text = (el: Element | null | undefined) => el?.textContent?.trim() ?? '';

  const name = (attr(doc.querySelector('.js-ordering-table'), 'data-owner-name') ||
    text(doc.querySelector('title')).replace(/\s*-\s*Tackle Warehouse\s*$/i, '')).trim();
  const brand = attr(doc.querySelector('meta[itemprop="brand"]'), 'content');
  const mainImg = doc.querySelector('img[itemprop="image"]');
  const mainSrc = attr(mainImg, 'src');
  const image = largestFromSrcset(attr(mainImg, 'srcset')) || (mainSrc ? withWidth(mainSrc, 600) : null);

  const variants: TwVariant[] = [...doc.querySelectorAll('tr[itemprop="offers"]')].map((row) => {
    const styles: Record<string, string> = {};
    let thumb: string | null = null;
    row.querySelectorAll('.js-ordering-style').forEach((st) => {
      const key = text(st.querySelector('.js-ordering-style-name'));
      const val = text(st.querySelector('.js-ordering-style-item-name'));
      if (key && val) styles[key] = val;
      thumb ||= attr(st, 'data-stylethumb');
    });
    return {
      sku: attr(row, 'data-code') || attr(row.querySelector('meta[itemprop="sku"]'), 'content'),
      name: text(row.querySelector('.js-ordering-name')),
      price: Number(attr(row.querySelector('meta[itemprop="price"]'), 'content')) || null,
      upc: normalizeUpc(attr(row.querySelector('meta[itemprop^="gtin"]'), 'content')),
      image: thumb ? withWidth(thumb, 600) : null,
      styles,
      color: styles.Color || null,
      size: Object.entries(styles).find(([k]) => /size|length|weight|count|pack/i.test(k))?.[1] || null,
      in_stock: text(row.querySelector('.js-ordering-available')) || null,
    };
  });

  if (!name && !variants.length) throw new Error("That page didn't look like a Tackle Warehouse product");
  return { name, brand, image, url: url.toString(), category: guessCategory(name), variants };
}

// ---- Optional barcode lookup relay ----

const RELAY_KEY = 'upcRelayUrl';

export function getUpcRelay() {
  try {
    return localStorage.getItem(RELAY_KEY) || import.meta.env.VITE_UPC_RELAY || '';
  } catch {
    return import.meta.env.VITE_UPC_RELAY || '';
  }
}

export function setUpcRelay(url: string) {
  try {
    if (url.trim()) localStorage.setItem(RELAY_KEY, url.trim());
    else localStorage.removeItem(RELAY_KEY);
  } catch { /* storage blocked */ }
}

/**
 * The free UPCitemdb lookup only answers its own website, so it goes through a tiny relay
 * (worker/upc-relay.js on Cloudflare's free tier). Without one, unknown barcodes just aren't prefilled.
 */
export async function lookupUpc(code: string): Promise<UpcSuggestion | null> {
  const relay = getUpcRelay();
  const upc = normalizeUpc(code);
  if (!relay || !upc) return null;
  try {
    const u = new URL(relay);
    u.searchParams.set('upc', upc.padStart(12, '0'));
    const res = await fetch(u, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) return null;
    const item = (await res.json()).items?.[0];
    if (!item) return null;
    return {
      name: item.title || null,
      brand: item.brand || null,
      color: item.color || null,
      size: item.size || null,
      image: item.images?.find((i: string) => /^https:/.test(i)) || null,
      category: guessCategory(item.title),
    };
  } catch {
    return null;
  }
}

// ---- Photos ----

/** Downloads a product image onto the phone so it shows offline. Falls back to the link if the site won't allow it. */
export async function cacheImage(remoteUrl: string) {
  try {
    const res = await fetch(remoteUrl, { credentials: 'omit' });
    const blob = await res.blob();
    if (!res.ok || !blob.type.startsWith('image/')) throw new Error();
    return await saveImage(blob);
  } catch {
    return remoteUrl;
  }
}

/** Phone photos are several MB; shrink to 1200px JPEG before storing. */
export async function savePhoto(file: File) {
  let blob: Blob = file;
  try {
    const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
    const scale = Math.min(1, 1200 / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(bitmap.width * scale);
    canvas.height = Math.round(bitmap.height * scale);
    canvas.getContext('2d')!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    bitmap.close();
    blob = await new Promise<Blob>((resolve, reject) =>
      canvas.toBlob((b) => (b ? resolve(b) : reject(new Error())), 'image/jpeg', 0.82));
  } catch {
    // Older browsers without createImageBitmap: store the original.
  }
  return saveImage(blob);
}
