// Optional Cloudflare Worker that lets the phone app ask UPCitemdb's free lookup about unknown barcodes.
// UPCitemdb only answers requests from its own website, so the phone can't call it directly.
// Deploy steps are in worker/README.md.

const ALLOWED_ORIGIN = '*'; // or your app's address, e.g. 'https://kevinkeyt.github.io'

export default {
  async fetch(request) {
    const cors = {
      'Access-Control-Allow-Origin': ALLOWED_ORIGIN,
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
    };
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors });

    const upc = new URL(request.url).searchParams.get('upc') || '';
    if (request.method !== 'GET' || !/^\d{6,14}$/.test(upc)) {
      return new Response(JSON.stringify({ error: 'Pass ?upc=<digits>' }), {
        status: 400, headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    const res = await fetch(`https://api.upcitemdb.com/prod/trial/lookup?upc=${upc}`, {
      headers: { Accept: 'application/json' },
      cf: { cacheTtl: 86400, cacheEverything: true }, // repeat scans of the same code don't use up the daily limit
    });
    return new Response(res.body, {
      status: res.status,
      headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=86400' },
    });
  },
};
