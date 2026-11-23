# Barcode lookup relay

When you scan a package that isn't in your tackle yet, the app fills in its name and brand from
[UPCitemdb](https://www.upcitemdb.com/)'s free lookup (about 100 lookups a day). UPCitemdb only answers its own
website, so the phone goes through this small Cloudflare Worker. Without it, everything else still works; new items
just start blank.

The app has the relay address built in (`UpcLookup.defaultRelay` in
[`ios/TackleTracker/Services/UpcLookup.swift`](../ios/TackleTracker/Services/UpcLookup.swift)), and it can be changed
on the phone under **More → Barcode lookup**.

## Deploying

With a Cloudflare account (the free plan is plenty):

```bash
npm run deploy:worker
```

The first run opens a browser to log in to Cloudflare. It prints the worker's address, like
`https://tackletracker-upc-relay.<your-subdomain>.workers.dev`.

The iOS app isn't a website, so it's always allowed. Websites are blocked, so other sites can't use up the daily
lookup limit. To let a website use the relay, list its address in `ALLOWED_ORIGINS` in [`wrangler.toml`](wrangler.toml)
and deploy again.
