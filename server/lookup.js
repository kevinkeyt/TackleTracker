import * as cheerio from 'cheerio';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { IMAGE_DIR, normalizeUpc } from './db.js';

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';
const TW_HOST = 'www.tacklewarehouse.com';

export function twSearchUrl(text) {
  return `https://${TW_HOST}/search-tackle.html?searchtext=${encodeURIComponent(text)}`;
}

/** Best guess at our category from a product title. The user can always change it. */
export function guessCategory(title = '') {
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

/**
 * Reads a Tackle Warehouse product page (…/descpage-XXXX.html). Each color/size is an
 * schema.org Offer row carrying its own SKU, price, GTIN and swatch image.
 */
export async function fetchTwProduct(rawUrl) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    throw Object.assign(new Error('That is not a valid URL'), { status: 400 });
  }
  if (!/(^|\.)tacklewarehouse\.com$/.test(url.hostname) || !/descpage-/i.test(url.pathname)) {
    throw Object.assign(new Error('Paste a Tackle Warehouse product page link (it contains "descpage-")'), { status: 400 });
  }
  url.protocol = 'https:';
  url.hostname = TW_HOST;
  url.hash = '';

  const res = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'text/html' } });
  if (!res.ok) throw Object.assign(new Error(`Tackle Warehouse returned ${res.status}`), { status: 502 });
  const $ = cheerio.load(await res.text());

  const name = ($('.js-ordering-table').attr('data-owner-name') || $('title').text().replace(/\s*-\s*Tackle Warehouse\s*$/i, '')).trim();
  const brand = $('meta[itemprop="brand"]').attr('content') || null;
  const mainImg = $('img[itemprop="image"]').first();
  const image = largestFromSrcset(mainImg.attr('srcset')) || mainImg.attr('src') || null;

  const variants = [];
  $('tr[itemprop="offers"]').each((_, el) => {
    const row = $(el);
    const styles = {};
    let thumb = null;
    row.find('.js-ordering-style').each((_, s) => {
      const st = $(s);
      const key = st.find('.js-ordering-style-name').text().trim();
      const val = st.find('.js-ordering-style-item-name').text().trim();
      if (key && val) styles[key] = val;
      thumb ||= st.attr('data-stylethumb') || null;
    });
    const gtin = row.find('meta[itemprop^="gtin"]').attr('content');
    variants.push({
      sku: row.attr('data-code') || row.find('meta[itemprop="sku"]').attr('content') || null,
      name: row.find('.js-ordering-name').text().trim(),
      price: Number(row.find('meta[itemprop="price"]').attr('content')) || null,
      upc: normalizeUpc(gtin),
      image: thumb ? withWidth(thumb, 600) : null,
      styles,
      color: styles.Color || null,
      size: Object.entries(styles).find(([k]) => /size|length|weight|count|pack/i.test(k))?.[1] || null,
      in_stock: row.find('.js-ordering-available').text().trim() || null,
    });
  });

  return { name, brand, image, url: url.toString(), category: guessCategory(name), variants };
}

function largestFromSrcset(srcset) {
  if (!srcset) return null;
  const best = srcset.split(',').map((s) => s.trim().split(/\s+/)).map(([u, w]) => [u, parseInt(w, 10) || 0])
    .sort((a, b) => b[1] - a[1])[0];
  return best ? withWidth(best[0], 600) : null;
}

function withWidth(imgUrl, width) {
  try {
    const u = new URL(imgUrl);
    if (u.searchParams.has('path')) u.searchParams.set('nw', String(width));
    return u.toString();
  } catch {
    return imgUrl;
  }
}

/**
 * Free UPC lookup (UPCitemdb trial tier, ~100 lookups/day, no key) to prefill name and brand
 * for packages Tackle Warehouse doesn't tell us about.
 */
export async function lookupUpc(code) {
  const upc = normalizeUpc(code);
  if (!upc) return null;
  try {
    const res = await fetch(`https://api.upcitemdb.com/prod/trial/lookup?upc=${upc.padStart(12, '0')}`, {
      headers: { 'User-Agent': UA, Accept: 'application/json' },
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) return null;
    const item = (await res.json()).items?.[0];
    if (!item) return null;
    return {
      name: item.title || null,
      brand: item.brand || null,
      color: item.color || null,
      size: item.size || null,
      image: item.images?.find((i) => /^https:/.test(i)) || item.images?.[0] || null,
      category: guessCategory(item.title),
    };
  } catch {
    return null;
  }
}

/** Copies a remote product image into data/images so it shows in the tackle room without internet. */
export async function cacheImage(remoteUrl) {
  const u = new URL(remoteUrl);
  if (!/^https?:$/.test(u.protocol)) throw Object.assign(new Error('Unsupported image URL'), { status: 400 });
  const res = await fetch(u, { headers: { 'User-Agent': UA, Referer: `https://${TW_HOST}/` }, signal: AbortSignal.timeout(15000) });
  const type = res.headers.get('content-type') || '';
  if (!res.ok || !type.startsWith('image/')) throw Object.assign(new Error('Could not download that image'), { status: 502 });
  const buf = Buffer.from(await res.arrayBuffer());
  const ext = { 'image/png': '.png', 'image/webp': '.webp', 'image/gif': '.gif' }[type.split(';')[0]] || '.jpg';
  const file = crypto.createHash('sha1').update(remoteUrl).digest('hex').slice(0, 16) + ext;
  fs.writeFileSync(path.join(IMAGE_DIR, file), buf);
  return `/images/${file}`;
}
