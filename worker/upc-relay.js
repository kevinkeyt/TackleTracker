// Cloudflare Worker that lets the iOS app ask UPCitemdb's free lookup about unknown barcodes.
// UPCitemdb only answers requests from its own website, so the phone can't call it directly.
// The iOS app sends no Origin header, so it's always allowed. Browsers always send one: websites are
// blocked unless listed in ALLOWED_ORIGINS (wrangler.toml), which keeps other sites from using up the
// daily lookup limit. Deploy steps are in worker/README.md.

export default {
  async fetch(request, env) {
    // Empty or unset means no websites; "*" means any.
    const allowed = (env.ALLOWED_ORIGINS ?? '').split(',').map((s) => s.trim()).filter(Boolean);
    const origin = request.headers.get('Origin');
    const allowOrigin = allowed.includes('*') ? '*' : allowed.includes(origin) ? origin : null;
    const cors = allowOrigin
      ? { 'Access-Control-Allow-Origin': allowOrigin, 'Access-Control-Allow-Methods': 'GET, OPTIONS', Vary: 'Origin' }
      : { Vary: 'Origin' };
    const json = (body, status) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

    if (origin && !allowOrigin) return json({ error: 'Origin not allowed' }, 403);
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors });

    const upc = new URL(request.url).searchParams.get('upc') || '';
    if (request.method !== 'GET' || !/^\d{6,14}$/.test(upc)) return json({ error: 'Pass ?upc=<digits>' }, 400);

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
