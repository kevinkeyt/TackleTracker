# Barcode lookup relay (optional)

When you scan a package that isn't in your tackle yet, the app can fill in its name and brand from
[UPCitemdb](https://www.upcitemdb.com/)'s free lookup (about 100 lookups a day). UPCitemdb only answers its own
website, so the phone needs this tiny relay. Without it, everything else still works; new items just start blank.

## Set it up (free, about 5 minutes)

1. Create a free account at <https://dash.cloudflare.com/sign-up>.
2. In the dashboard: **Workers & Pages → Create → Create Worker**. Name it `upc-relay`, then **Deploy**.
3. Click **Edit code**, replace everything with the contents of [`upc-relay.js`](upc-relay.js), and **Deploy** again.
4. Copy the worker's address (like `https://upc-relay.your-name.workers.dev`).
5. In TackleTracker on your phone: **More → Barcode lookup**, paste the address, **Save**.

Optionally set `ALLOWED_ORIGIN` in the code to your app's address so only your app can use the relay.
