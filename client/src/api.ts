import * as db from './db';
import { cacheImage, fetchTwProduct, lookupUpc, savePhoto, twSearchUrl } from './lookup';

export { isLow } from './db';
export { twSearchUrl } from './lookup';

export type Category = 'soft_plastic' | 'hard_bait' | 'terminal' | 'line' | 'rod' | 'reel' | 'other';

export const CATEGORIES: { id: Category; label: string; types: string[] }[] = [
  { id: 'soft_plastic', label: 'Soft plastics', types: ['Worm', 'Stick bait', 'Craw', 'Creature', 'Swimbait', 'Fluke', 'Tube', 'Grub', 'Trailer', 'Ned', 'Frog'] },
  { id: 'hard_bait', label: 'Hard baits', types: ['Crankbait', 'Jerkbait', 'Topwater', 'Lipless', 'Spinnerbait', 'Bladed jig', 'Jig', 'Swimbait', 'Glide bait', 'Buzzbait', 'Spoon', 'Frog'] },
  { id: 'terminal', label: 'Terminal', types: ['Hooks', 'Weights', 'Jig heads', 'Swivels', 'Bobber stops', 'Beads', 'Split rings'] },
  { id: 'line', label: 'Line', types: ['Fluorocarbon', 'Monofilament', 'Braid'] },
  { id: 'rod', label: 'Rods', types: ['Casting', 'Spinning'] },
  { id: 'reel', label: 'Reels', types: ['Baitcasting', 'Spinning'] },
  { id: 'other', label: 'Other', types: [] },
];

export const categoryLabel = (c: string) => CATEGORIES.find((x) => x.id === c)?.label ?? 'Other';

export const UNITS = ['pack', 'each', 'bag', 'spool', 'box'];

/** Extra fields worth tracking for gear that isn't sold in packs. */
export const SPEC_FIELDS: Partial<Record<Category, string[]>> = {
  rod: ['Length', 'Power', 'Action', 'Pieces', 'Line rating', 'Lure rating'],
  reel: ['Gear ratio', 'Retrieve', 'Size', 'Line on it'],
  line: ['Test (lb)', 'Yards'],
};

export interface Item {
  id: number;
  name: string;
  brand: string | null;
  category: Category;
  type: string | null;
  color: string | null;
  size: string | null;
  quantity: number;
  unit: string;
  min_quantity: number;
  location: string | null;
  upc: string | null;
  sku: string | null;
  price: number | null;
  image_url: string | null;
  product_url: string | null;
  specs: Record<string, string>;
  notes: string | null;
  on_list: boolean;
  created_at: string;
  updated_at: string;
}

export type ItemInput = Omit<Item, 'id' | 'created_at' | 'updated_at'>;

export interface UpcSuggestion {
  name: string | null;
  brand: string | null;
  color: string | null;
  size: string | null;
  image: string | null;
  category: Category;
}

export interface ScanResult {
  upc: string;
  owned: Item[];
  suggestion: UpcSuggestion | null;
  search_url: string;
}

export interface TwVariant {
  sku: string | null;
  name: string;
  price: number | null;
  upc: string | null;
  image: string | null;
  styles: Record<string, string>;
  color: string | null;
  size: string | null;
  in_stock: string | null;
}

export interface TwProduct {
  name: string;
  brand: string | null;
  image: string | null;
  url: string;
  category: Category;
  variants: TwVariant[];
}

export interface CategoryStats {
  category: Category;
  items: number;
  units: number;
  low: number;
  value: number;
}

/** All data lives on this device; these calls never need the internet except the lookups. */
export const api = {
  items: (params: { low?: boolean } = {}) => db.listItems(params),
  item: (id: number | string) => db.getItem(Number(id)),
  create: (item: Partial<ItemInput>) => db.createItem(item),
  update: (id: number, item: Partial<ItemInput>) => db.updateItem(id, item),
  adjust: (id: number, delta: number) => db.adjustQuantity(id, delta),
  remove: (id: number) => db.deleteItem(id),
  stats: () => db.stats(),
  scan: async (code: string): Promise<ScanResult> => {
    const upc = db.normalizeUpc(code);
    if (!upc) throw new Error('No digits in that barcode');
    const owned = await db.findByUpc(upc);
    const suggestion = owned.length ? null : await lookupUpc(upc);
    return { upc, owned, suggestion, search_url: twSearchUrl(suggestion?.name || upc) };
  },
  twProduct: (url: string) => fetchTwProduct(url),
  cacheImage: async (url: string) => ({ url: await cacheImage(url) }),
  uploadImage: async (file: File) => ({ url: await savePhoto(file) }),
  exportBackup: () => db.exportBackup(),
  importBackup: (data: unknown, replace: boolean) => db.importBackup(data, { replace }),
};

/** Where the Shop button goes: the saved product page, else a Tackle Warehouse search for it. */
export function shopUrl(it: Pick<Item, 'product_url' | 'brand' | 'name' | 'color'>) {
  if (it.product_url) return it.product_url;
  const text = [it.brand && !it.name.toLowerCase().startsWith(it.brand.toLowerCase()) ? it.brand : '', it.name, it.color]
    .filter(Boolean).join(' ');
  return twSearchUrl(text);
}

/** One-line summary; leaves out the brand when the name already starts with it ("Zoom Trick Worm"). */
export function describe(it: Pick<Item, 'name' | 'brand' | 'color' | 'size' | 'type'>) {
  const brand = it.brand && !it.name.toLowerCase().startsWith(it.brand.toLowerCase()) ? it.brand : null;
  return [brand, it.type, it.color, it.size].filter(Boolean).join(' · ');
}
