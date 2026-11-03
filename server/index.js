import express from 'express';
import multer from 'multer';
import selfsigned from 'selfsigned';
import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import * as db from './db.js';
import { cacheImage, fetchTwProduct, lookupUpc, twSearchUrl } from './lookup.js';

const HTTP_PORT = Number(process.env.PORT || 3000);
const HTTPS_PORT = Number(process.env.HTTPS_PORT || 3443);
const ROOT = path.resolve(import.meta.dirname, '..');
const DIST = path.join(ROOT, 'dist');

const app = express();
app.use(express.json({ limit: '10mb' }));

const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res)).catch(next);
const notFound = () => Object.assign(new Error('Not found'), { status: 404 });

app.get('/api/items', (req, res) => {
  res.json(db.listItems({ q: req.query.q, category: req.query.category, low: req.query.low === '1' }));
});

app.get('/api/items/:id', (req, res) => {
  const item = db.getItem(req.params.id);
  if (!item) throw notFound();
  res.json(item);
});

app.post('/api/items', (req, res) => res.status(201).json(db.createItem(req.body)));

app.put('/api/items/:id', (req, res) => {
  if (!db.getItem(req.params.id)) throw notFound();
  res.json(db.updateItem(req.params.id, req.body));
});

app.post('/api/items/:id/adjust', (req, res) => {
  if (!db.getItem(req.params.id)) throw notFound();
  res.json(db.adjustQuantity(req.params.id, req.body.delta));
});

app.delete('/api/items/:id', (req, res) => {
  if (!db.deleteItem(req.params.id)) throw notFound();
  res.status(204).end();
});

app.get('/api/stats', (_req, res) => res.json(db.stats()));

// Scan result: what you already own with this barcode, plus a best-effort description if you own none.
app.get('/api/scan/:code', wrap(async (req, res) => {
  const upc = db.normalizeUpc(req.params.code);
  if (!upc) throw Object.assign(new Error('No digits in that barcode'), { status: 400 });
  const owned = db.findByUpc(upc);
  const suggestion = owned.length ? null : await lookupUpc(upc);
  res.json({ upc, owned, suggestion, search_url: twSearchUrl(suggestion?.name || upc) });
}));

app.post('/api/tw/product', wrap(async (req, res) => res.json(await fetchTwProduct(req.body.url))));

app.get('/api/tw/search-url', (req, res) => res.json({ url: twSearchUrl(String(req.query.q || '')) }));

app.post('/api/images/cache', wrap(async (req, res) => res.json({ url: await cacheImage(req.body.url) })));

const upload = multer({
  storage: multer.diskStorage({
    destination: db.IMAGE_DIR,
    filename: (_req, file, cb) => cb(null, crypto.randomUUID().slice(0, 12) + (path.extname(file.originalname).toLowerCase() || '.jpg')),
  }),
  limits: { fileSize: 15 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => cb(null, file.mimetype.startsWith('image/')),
});
app.post('/api/images/upload', upload.single('image'), (req, res) => {
  if (!req.file) throw Object.assign(new Error('No image received'), { status: 400 });
  res.json({ url: `/images/${req.file.filename}` });
});

app.get('/api/export.json', (_req, res) => {
  res.attachment(`tackle-${new Date().toISOString().slice(0, 10)}.json`).json(db.listItems());
});

app.get('/api/export.csv', (_req, res) => {
  const cols = ['name', 'brand', 'category', 'type', 'color', 'size', 'quantity', 'unit', 'min_quantity', 'location', 'upc', 'sku', 'price', 'product_url', 'notes'];
  const esc = (v) => (v == null ? '' : /[",\n]/.test(String(v)) ? `"${String(v).replace(/"/g, '""')}"` : String(v));
  const csv = [cols.join(','), ...db.listItems().map((it) => cols.map((c) => esc(it[c])).join(','))].join('\n');
  res.attachment(`tackle-${new Date().toISOString().slice(0, 10)}.csv`).type('text/csv').send(csv);
});

app.post('/api/import', (req, res) => {
  const items = Array.isArray(req.body) ? req.body : req.body.items;
  if (!Array.isArray(items)) throw Object.assign(new Error('Expected a JSON array of items'), { status: 400 });
  res.json({ imported: db.importItems(items, { replace: req.query.replace === '1' }) });
});

app.use('/api', () => { throw notFound(); });
app.use('/images', express.static(db.IMAGE_DIR, { maxAge: '30d', immutable: true }));

if (fs.existsSync(DIST)) {
  app.use(express.static(DIST));
  app.get('*', (_req, res) => res.sendFile(path.join(DIST, 'index.html')));
}

app.use((err, _req, res, _next) => {
  if (!err.status) console.error(err);
  res.status(err.status || 500).json({ error: err.message || 'Something went wrong' });
});

function lanAddresses() {
  return Object.values(os.networkInterfaces()).flat()
    .filter((a) => a && a.family === 'IPv4' && !a.internal).map((a) => a.address);
}

/** Self-signed cert so phone browsers allow camera access over the LAN. Regenerated when the Mac's IP changes. */
function loadCert() {
  const dir = path.join(ROOT, '.certs');
  const ips = lanAddresses();
  const metaFile = path.join(dir, 'ips.json');
  if (fs.existsSync(metaFile) && JSON.parse(fs.readFileSync(metaFile, 'utf8')).join() === ips.join()) {
    return { key: fs.readFileSync(path.join(dir, 'key.pem')), cert: fs.readFileSync(path.join(dir, 'cert.pem')) };
  }
  const pems = selfsigned.generate([{ name: 'commonName', value: 'TackleTracker' }], {
    days: 825, keySize: 2048, algorithm: 'sha256',
    extensions: [{ name: 'subjectAltName', altNames: [
      { type: 2, value: 'localhost' }, { type: 2, value: `${os.hostname()}` },
      { type: 7, ip: '127.0.0.1' }, ...ips.map((ip) => ({ type: 7, ip })),
    ] }],
  });
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'key.pem'), pems.private);
  fs.writeFileSync(path.join(dir, 'cert.pem'), pems.cert);
  fs.writeFileSync(metaFile, JSON.stringify(ips));
  return { key: pems.private, cert: pems.cert };
}

http.createServer(app).listen(HTTP_PORT, () => {
  console.log(`TackleTracker API on http://localhost:${HTTP_PORT}`);
});
https.createServer(loadCert(), app).listen(HTTPS_PORT, () => {
  if (!fs.existsSync(DIST)) return;
  console.log('Open on your phone (same Wi-Fi):');
  for (const ip of lanAddresses()) console.log(`  https://${ip}:${HTTPS_PORT}`);
});
