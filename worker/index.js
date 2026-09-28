// Sends every request to https://trymeth.com, serves the static site, and answers
// /api/visitors with the number of visits Cloudflare Web Analytics saw recently (the last 24 hours).
// /api/email-link emails the download link to someone browsing on a phone (Cloudflare Email Service).
const ACCOUNT = 'd801fe59adab888d7a28d3a7a7d181e4';
const SITE_TAG = 'f91a6172b9d341c78547d934fe54cbc5'; // Web Analytics site for trymeth.com
const CACHE_SECONDS = 60;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.protocol === 'http:' || url.hostname === 'www.trymeth.com') {
      url.protocol = 'https:';
      url.hostname = 'trymeth.com';
      return Response.redirect(url.toString(), 301);
    }
    if (url.pathname === '/api/visitors') return visitors(request, env, ctx);
    if (url.pathname === '/api/email-link') return emailLink(request, env);
    return env.ASSETS.fetch(request);
  },
};

async function visitors(request, env, ctx) {
  // Cloudflare's edge keeps the answer for a minute; browsers never cache it (the zone's
  // browser-cache TTL would otherwise stretch any max-age to hours).
  const cache = caches.default;
  const key = new Request('https://trymeth.com/api/visitors');
  const cached = await cache.match(key);
  if (cached) return fresh(await cached.text(), cached.status);

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
    // Remember the failure briefly so a broken token doesn't send every page view to the API.
    const body = JSON.stringify({ error: 'unavailable' });
    ctx.waitUntil(cache.put(key, new Response(body, { status: 503, headers: { 'Cache-Control': 'max-age=30' } })));
    return fresh(body, 503);
  }
  const body = JSON.stringify({ visitors: count, window: '24h' });
  ctx.waitUntil(cache.put(key, new Response(body, { headers: { 'Cache-Control': `max-age=${CACHE_SECONDS}` } })));
  return fresh(body);
}

function fresh(body, status = 200) {
  return new Response(body, { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
}

// ---- Email me the download link ----------------------------------------------------------
// The message is fixed; the only input is the recipient. Guarded by Turnstile, a honeypot,
// an Origin check and per-IP / per-recipient rate limits. The address is not stored.
const DOWNLOAD = 'https://trymeth.com/download/Meth.dmg';
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

async function emailLink(request, env) {
  const enabled = env.EMAIL_LINK_ENABLED === 'true';
  if (request.method === 'GET') return fresh(JSON.stringify({ enabled }));
  if (request.method !== 'POST') return fresh(JSON.stringify({ error: 'method' }), 405);
  if (!enabled) return fresh(JSON.stringify({ error: 'disabled' }), 503);
  if (request.headers.get('Origin') !== 'https://trymeth.com') return fresh(JSON.stringify({ error: 'origin' }), 403);

  let body;
  try { body = await request.json(); } catch { return fresh(JSON.stringify({ error: 'invalid' }), 400); }
  const email = String(body?.email || '').trim().toLowerCase();
  if (body?.company) return fresh(JSON.stringify({ ok: true })); // honeypot: pretend it worked
  if (email.length > 254 || !EMAIL_RE.test(email)) return fresh(JSON.stringify({ error: 'email' }), 400);

  const ip = request.headers.get('CF-Connecting-IP') || '';
  const [byIp, byRecipient] = await Promise.all([
    env.EMAIL_LIMIT.limit({ key: `ip:${ip}` }),
    env.EMAIL_LIMIT.limit({ key: `to:${email}` }),
  ]);
  if (!byIp.success || !byRecipient.success) return fresh(JSON.stringify({ error: 'rate' }), 429);

  const form = new FormData();
  form.append('secret', env.TURNSTILE_SECRET);
  form.append('response', String(body?.token || ''));
  if (ip) form.append('remoteip', ip);
  const check = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', { method: 'POST', body: form })
    .then((r) => r.json()).catch(() => null);
  if (!check?.success || check.hostname !== 'trymeth.com') return fresh(JSON.stringify({ error: 'bot' }), 403);

  try {
    await env.EMAIL.send({
      to: email,
      from: { email: 'download@trymeth.com', name: 'Meth' },
      subject: 'Your Meth download link',
      text: `Meth for your Mac: keep your Mac awake, even with the lid closed.\n\nOpen this link on your Mac to download Meth (free, macOS 15 or later):\n${DOWNLOAD}\n\nThen drag Meth to Applications and look for the eye in your menu bar.\n\nhttps://trymeth.com\n\nYou got this because someone entered this address on trymeth.com. We don't store it and won't email you again.`,
      html: mailHtml(),
    });
  } catch {
    return fresh(JSON.stringify({ error: 'send' }), 502);
  }
  return fresh(JSON.stringify({ ok: true }));
}

function mailHtml() {
  return `<!doctype html><html><body style="margin:0;background:#fafaf9;font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',Helvetica,Arial,sans-serif;color:#111110">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:40px 16px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border:1px solid #e4e4e0;border-radius:20px">
<tr><td style="padding:36px 32px">
<p style="margin:0 0 20px;font-size:15px;font-weight:700">&#128065; Meth</p>
<h1 style="margin:0 0 10px;font-size:28px;line-height:1.1;letter-spacing:-0.03em">Meth for your Mac.</h1>
<p style="margin:0 0 26px;font-size:16px;line-height:1.5;color:#6b6b66">Keep your Mac awake, even with the lid closed. Open this email on your Mac to download it.</p>
<a href="${DOWNLOAD}" style="display:inline-block;background:#111110;color:#fafaf9;text-decoration:none;font-weight:600;font-size:16px;padding:14px 26px;border-radius:999px">Download Meth</a>
<p style="margin:22px 0 0;font-size:14px;line-height:1.5;color:#6b6b66">Free &middot; macOS 15 or later. Drag Meth to Applications, then look for the eye in your menu bar.</p>
</td></tr></table>
<p style="max-width:480px;margin:18px auto 0;font-size:12px;line-height:1.5;color:#9a9a94">You got this because someone entered this address on <a href="https://trymeth.com" style="color:#9a9a94">trymeth.com</a>. We don't store it and won't email you again.</p>
</td></tr></table></body></html>`;
}
