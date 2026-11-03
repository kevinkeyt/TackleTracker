# TackleTracker

Keep track of your soft plastics, hard baits, terminal tackle, line, rods and reels from your phone in the tackle room.

- **Scan a barcode** to see if you already own it (and how many), or add it if you don't. Works in the store too, so you don't buy what you already have.
- **Scan modes**: *Add +1* counts packages as you shelve them; *Take out −1* removes one per scan when you load the boat or use something up. Each scan can be undone.
- **Fill in from Tackle Warehouse**: paste a product link, tap your color, and the name, brand, photo, price, SKU and UPC are filled in for you. Photos are saved on your computer.
- **Reorder list**: set a "reorder at" level per item. Anything at or below it (or added to the list by hand) shows up with a **Shop** button that goes back to Tackle Warehouse.
- Backups as JSON or CSV from the **More** tab.

## Running it

Requires Node 22.13 or later. Everything runs on your Mac, and the database is `data/tackle.db`.

```bash
npm install
```

```bash
npm start
```

It prints a list like `https://192.168.1.29:3443`. Open that on your phone while you're on the same Wi-Fi.

- The certificate is self-signed, so the phone will warn you the first time. On iPhone, tap **Show Details**, then **visit this website**. HTTPS is required for live camera scanning. If the warning gets in the way, **Snap photo of barcode** still works over plain `http://<mac-ip>:3000`.
- In Safari, tap **Share**, then **Add to Home Screen**, and it opens like an app.
- Your Mac has to be awake and running the server for the phone to reach it.

### Developing

```bash
npm run dev
```

This runs the API on :3000 and the Vite dev server with hot reload on https://localhost:5173 (also reachable from your phone on your LAN).

## How the lookups work

- **Tackle Warehouse**: only product pages (`…/descpage-XXXX.html`) are fetched, and only when you press Load. Each color on the page lists its own UPC, price and swatch image. Search links open in your browser; the app does not scrape search results.
- **Unknown barcodes** are looked up in the free [UPCitemdb](https://www.upcitemdb.com/) trial API (about 100 lookups a day) to prefill the name and brand.

## Layout

```
server/   Express API, SQLite (node:sqlite), Tackle Warehouse + UPC lookups
client/   React + Vite phone UI, ZXing barcode scanner
data/     Your database and saved images (git-ignored; back this up)
```
