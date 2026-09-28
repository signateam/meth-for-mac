// Sends every request to https://trymeth.com, serves the static site, and answers
// /api/visitors with the number of visits Cloudflare Web Analytics saw in the last 24 hours.
const ACCOUNT = 'd801fe59adab888d7a28d3a7a7d181e4';
const SITE_TAG = 'f91a6172b9d341c78547d934fe54cbc5'; // Web Analytics site for trymeth.com
const CACHE_SECONDS = 300;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.protocol === 'http:' || url.hostname === 'www.trymeth.com') {
      url.protocol = 'https:';
      url.hostname = 'trymeth.com';
      return Response.redirect(url.toString(), 301);
    }
    if (url.pathname === '/api/visitors') return visitors(request, env, ctx);
    return env.ASSETS.fetch(request);
  },
};

async function visitors(request, env, ctx) {
  const cache = caches.default;
  const key = new Request('https://trymeth.com/api/visitors');
  const cached = await cache.match(key);
  if (cached) return cached;

  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const query = `{ viewer { accounts(filter: { accountTag: "${ACCOUNT}" }) {
    rumPageloadEventsAdaptiveGroups(limit: 1, filter: { siteTag: "${SITE_TAG}", datetime_geq: "${since}" }) { sum { visits } }
  } } }`;

  let count = null;
  try {
    const res = await fetch('https://api.cloudflare.com/client/v4/graphql', {
      method: 'POST',
      headers: { Authorization: `Bearer ${env.CF_ANALYTICS_TOKEN}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query }),
    });
    const data = await res.json();
    const groups = data?.data?.viewer?.accounts?.[0]?.rumPageloadEventsAdaptiveGroups;
    if (Array.isArray(groups)) count = groups[0]?.sum?.visits ?? 0;
  } catch {}

  if (count === null) {
    return Response.json({ error: 'unavailable' }, { status: 503, headers: { 'Cache-Control': 'no-store' } });
  }
  const response = Response.json({ visitors: count, window: '24h' }, {
    headers: { 'Cache-Control': `public, max-age=${CACHE_SECONDS}` },
  });
  ctx.waitUntil(cache.put(key, response.clone()));
  return response;
}
