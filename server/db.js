import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';

export const DATA_DIR = process.env.TT_DATA_DIR || path.resolve(import.meta.dirname, '..', 'data');
export const IMAGE_DIR = path.join(DATA_DIR, 'images');
fs.mkdirSync(IMAGE_DIR, { recursive: true });

export const CATEGORIES = ['soft_plastic', 'hard_bait', 'terminal', 'line', 'rod', 'reel', 'other'];

const db = new DatabaseSync(path.join(DATA_DIR, 'tackle.db'));
db.exec(`
  PRAGMA journal_mode = WAL;
  CREATE TABLE IF NOT EXISTS items (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT NOT NULL,
    brand         TEXT,
    category      TEXT NOT NULL DEFAULT 'other',
    type          TEXT,
    color         TEXT,
    size          TEXT,
    quantity      INTEGER NOT NULL DEFAULT 0,
    unit          TEXT NOT NULL DEFAULT 'pack',
    min_quantity  INTEGER NOT NULL DEFAULT 0,
    location      TEXT,
    upc           TEXT,
    sku           TEXT,
    price         REAL,
    image_url     TEXT,
    product_url   TEXT,
    specs         TEXT,
    notes         TEXT,
    on_list       INTEGER NOT NULL DEFAULT 0,
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at    TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE INDEX IF NOT EXISTS items_upc ON items(upc);
`);

const FIELDS = ['name', 'brand', 'category', 'type', 'color', 'size', 'quantity', 'unit', 'min_quantity',
  'location', 'upc', 'sku', 'price', 'image_url', 'product_url', 'specs', 'notes', 'on_list'];

/** UPC-A (12), EAN-13 and GTIN-14 of the same product differ only by leading zeros. */
export function normalizeUpc(code) {
  const digits = String(code ?? '').replace(/\D/g, '').replace(/^0+/, '');
  return digits || null;
}

function toRow(row) {
  if (!row) return row;
  return { ...row, on_list: !!row.on_list, specs: row.specs ? JSON.parse(row.specs) : {} };
}

function clean(input) {
  const out = {};
  for (const f of FIELDS) {
    if (!(f in input)) continue;
    let v = input[f];
    if (typeof v === 'string') v = v.trim();
    if (v === '') v = null;
    if (f === 'upc') v = normalizeUpc(v);
    if (f === 'specs') v = v && Object.keys(v).length ? JSON.stringify(v) : null;
    if (f === 'on_list') v = v ? 1 : 0;
    if (f === 'quantity' || f === 'min_quantity') v = Math.max(0, parseInt(v, 10) || 0);
    if (f === 'price') v = v == null ? null : Number(v) || null;
    if (f === 'category' && !CATEGORIES.includes(v)) v = 'other';
    out[f] = v;
  }
  return out;
}

export function listItems({ q, category, low } = {}) {
  const where = [];
  const params = {};
  if (category && CATEGORIES.includes(category)) {
    where.push('category = :category');
    params.category = category;
  }
  if (low) where.push('((min_quantity > 0 AND quantity <= min_quantity) OR on_list = 1)');
  if (q) {
    // Every word must match somewhere, so "green pumpkin trick" finds the Zoom Trick Worm in Green Pumpkin.
    q.trim().split(/\s+/).forEach((word, i) => {
      where.push(`(name || ' ' || IFNULL(brand,'') || ' ' || IFNULL(type,'') || ' ' || IFNULL(color,'') || ' ' ||
        IFNULL(size,'') || ' ' || IFNULL(location,'') || ' ' || IFNULL(upc,'') || ' ' || IFNULL(sku,'')) LIKE :w${i}`);
      params[`w${i}`] = `%${word}%`;
    });
  }
  const sql = `SELECT * FROM items ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
    ORDER BY category, brand COLLATE NOCASE, name COLLATE NOCASE, color COLLATE NOCASE`;
  return db.prepare(sql).all(params).map(toRow);
}

export function getItem(id) {
  return toRow(db.prepare('SELECT * FROM items WHERE id = ?').get(id));
}

export function findByUpc(code) {
  const upc = normalizeUpc(code);
  if (!upc) return [];
  return db.prepare('SELECT * FROM items WHERE upc = ?').all(upc).map(toRow);
}

export function createItem(input) {
  const data = clean(input);
  if (!data.name) throw Object.assign(new Error('Name is required'), { status: 400 });
  const cols = Object.keys(data);
  const info = db.prepare(`INSERT INTO items (${cols.join(',')}) VALUES (${cols.map((c) => ':' + c).join(',')})`).run(data);
  return getItem(info.lastInsertRowid);
}

export function updateItem(id, input) {
  const data = clean(input);
  delete data.id;
  if ('name' in data && !data.name) throw Object.assign(new Error('Name is required'), { status: 400 });
  const cols = Object.keys(data);
  if (cols.length) {
    db.prepare(`UPDATE items SET ${cols.map((c) => `${c} = :${c}`).join(', ')}, updated_at = datetime('now') WHERE id = :id`)
      .run({ ...data, id });
  }
  return getItem(id);
}

export function adjustQuantity(id, delta) {
  db.prepare(`UPDATE items SET quantity = MAX(0, quantity + ?), updated_at = datetime('now') WHERE id = ?`)
    .run(parseInt(delta, 10) || 0, id);
  return getItem(id);
}

export function deleteItem(id) {
  return db.prepare('DELETE FROM items WHERE id = ?').run(id).changes > 0;
}

export function stats() {
  return db.prepare(`SELECT category, COUNT(*) AS items, SUM(quantity) AS units,
      SUM(CASE WHEN (min_quantity > 0 AND quantity <= min_quantity) OR on_list = 1 THEN 1 ELSE 0 END) AS low,
      SUM(quantity * IFNULL(price, 0)) AS value
    FROM items GROUP BY category`).all().map((r) => ({ ...r }));
}

export function importItems(items, { replace = false } = {}) {
  db.exec('BEGIN');
  try {
    if (replace) db.exec('DELETE FROM items');
    let n = 0;
    for (const it of items) {
      const { id, created_at, updated_at, ...rest } = it;
      createItem(rest);
      n++;
    }
    db.exec('COMMIT');
    return n;
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}
