# TackleTracker

Keep track of your soft plastics, hard baits, terminal tackle, line, rods and reels from your phone in the tackle room.
It's a web app you add to your home screen. **All of your data stays on your phone**, so there is no server or computer to keep running.

- **Scan a barcode** to see if you already own it (and how many), or add it if you don't. Works in the store too, so you don't buy what you already have.
- **Scan modes**: *Add +1* counts packages as you shelve them; *Take out −1* removes one per scan when you load the boat or use something up. Each scan can be undone.
- **Fill in from Tackle Warehouse**: paste a product link, tap your color, and the name, brand, photo, price, SKU and UPC are filled in for you. Photos are saved on the phone.
- **Reorder list**: set a "reorder at" level per item. Anything at or below it (or added to the list by hand) shows up with a **Shop** button that goes back to Tackle Warehouse.
- **Works offline** once installed. Only Tackle Warehouse import and the Shop links need a connection.
- **Backups** to Files / iCloud Drive (photos included) and spreadsheet (CSV) export from the **More** tab.

## Using it on your phone

1. Open the app's address in Safari (or Chrome on Android).
2. Tap **Share → Add to Home Screen**. It now opens like an app.
3. Every couple of weeks, use **More → Back up now** and choose **Save to Files**. The app reminds you if it's been a while.

Because the data lives only on the phone, deleting the home-screen app or clearing Safari's website data deletes your tackle list. A backup restores it.

## Hosting

The app is a folder of static files (`npm run build` → `dist/`), so any free static host works. This repo deploys to
**GitHub Pages** automatically on every push to `main` (`.github/workflows/deploy.yml`). To turn that on, go to the
repo's **Settings → Pages** and set **Source** to **GitHub Actions**. GitHub Pages needs a public repo on a free
account. The repo only contains code; your tackle data is never uploaded anywhere.

Cloudflare Pages or Netlify work too: build command `npm run build`, output folder `dist`.

## Barcode lookup for new items (optional)

Scanning always finds what you already own. To also prefill the name of packages you haven't added yet, set up the
free relay in [`worker/`](worker/README.md) and paste its address under **More → Barcode lookup**.

## Developing

Requires Node 22.13 or later.

```bash
npm install
```

```bash
npm run dev
```

The dev server runs at https://localhost:5173 and on your LAN (the address is printed), so you can try changes on
your phone. Accept the certificate warning; it's needed for camera access during development. Data you create in
development lives in that browser only.

## How the lookups work

- **Tackle Warehouse**: the phone reads a product page (`…/descpage-XXXX.html`) only when you press Load. Each color on
  the page lists its own UPC, price and swatch image. Search links open in your browser; the app doesn't scrape search
  results.
- **Unknown barcodes** go through the optional relay to the free UPCitemdb trial API (about 100 lookups a day).

## Layout

```
client/    React + Vite app: IndexedDB storage (db.ts), lookups (lookup.ts), ZXing scanner, service worker
worker/    Optional Cloudflare Worker relay for barcode lookups
```
