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

async function req<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, {
    ...init,
    headers: init?.body && !(init.body instanceof FormData) ? { 'Content-Type': 'application/json', ...init.headers } : init?.headers,
  });
  if (res.status === 204) return undefined as T;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `Request failed (${res.status})`);
  return data as T;
}

export const api = {
  items: (params: { q?: string; category?: string; low?: boolean } = {}) => {
    const qs = new URLSearchParams();
    if (params.q) qs.set('q', params.q);
    if (params.category) qs.set('category', params.category);
    if (params.low) qs.set('low', '1');
    return req<Item[]>(`/api/items?${qs}`);
  },
  item: (id: number | string) => req<Item>(`/api/items/${id}`),
  create: (item: Partial<ItemInput>) => req<Item>('/api/items', { method: 'POST', body: JSON.stringify(item) }),
  update: (id: number, item: Partial<ItemInput>) => req<Item>(`/api/items/${id}`, { method: 'PUT', body: JSON.stringify(item) }),
  adjust: (id: number, delta: number) => req<Item>(`/api/items/${id}/adjust`, { method: 'POST', body: JSON.stringify({ delta }) }),
  remove: (id: number) => req<void>(`/api/items/${id}`, { method: 'DELETE' }),
  stats: () => req<CategoryStats[]>('/api/stats'),
  scan: (code: string) => req<ScanResult>(`/api/scan/${encodeURIComponent(code)}`),
  twProduct: (url: string) => req<TwProduct>('/api/tw/product', { method: 'POST', body: JSON.stringify({ url }) }),
  cacheImage: (url: string) => req<{ url: string }>('/api/images/cache', { method: 'POST', body: JSON.stringify({ url }) }),
  uploadImage: (file: File) => {
    const body = new FormData();
    body.append('image', file);
    return req<{ url: string }>('/api/images/upload', { method: 'POST', body });
  },
  importItems: (items: unknown[], replace: boolean) =>
    req<{ imported: number }>(`/api/import${replace ? '?replace=1' : ''}`, { method: 'POST', body: JSON.stringify(items) }),
};

export const isLow = (it: Item) => it.min_quantity > 0 && it.quantity <= it.min_quantity;

export function twSearchUrl(text: string) {
  return `https://www.tacklewarehouse.com/search-tackle.html?searchtext=${encodeURIComponent(text)}`;
}

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
