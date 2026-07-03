// Cloudflare Worker — canary router
//
// One Worker is deployed per app (env.APP_NAME set per-deployment in
// wrangler.toml — see cdn/README.md), proxying to whichever Cloudflare
// Pages deployment URL is currently "stable" or "canary" for that app.
// Sticky per visitor via a cookie, so a page's HTML and its JS/CSS chunks
// never come from two different deployments.
//
// Unlike the CloudFront Functions design this replaced, a single Worker
// can read state, pick a target, fetch it, and set the response cookie —
// no split request/response function pair needed.
//
// KV keys (written by cdn/scripts/shift-canary.sh and promote.sh),
// namespaced per app since both apps share one KV namespace:
//   <app>.stableUrl      e.g. "https://a1b2c3d.my-app.pages.dev"
//   <app>.canaryUrl      e.g. "https://e4f5g6h.my-app.pages.dev"
//   <app>.canaryWeight   "0".."100" — percent of *new* visitors -> canary

function parseCookies(header) {
  const cookies = {};
  header.split(';').forEach((pair) => {
    const idx = pair.indexOf('=');
    if (idx === -1) return;
    cookies[pair.slice(0, idx).trim()] = pair.slice(idx + 1).trim();
  });
  return cookies;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const cookies = parseCookies(request.headers.get('Cookie') || '');

    const stableUrl = await env.CANARY_KV.get(`${env.APP_NAME}.stableUrl`);
    const canaryUrl = (await env.CANARY_KV.get(`${env.APP_NAME}.canaryUrl`)) || stableUrl;
    const canaryWeight = parseInt((await env.CANARY_KV.get(`${env.APP_NAME}.canaryWeight`)) || '0', 10);

    if (!stableUrl) {
      return new Response('Canary router misconfigured: no stableUrl in KV', { status: 502 });
    }

    let bucket = cookies['app-bucket'];
    if (bucket !== 'stable' && bucket !== 'canary') {
      bucket = Math.random() * 100 < canaryWeight ? 'canary' : 'stable';
    } else if (bucket === 'canary' && canaryWeight === 0) {
      // canary was retired (promoted or rolled back) — don't strand
      // previously-stickied visitors on a URL nobody is updating anymore
      bucket = 'stable';
    }

    const targetBase = bucket === 'canary' ? canaryUrl : stableUrl;
    const targetUrl = targetBase + url.pathname + url.search;

    const originResponse = await fetch(targetUrl, request);
    const response = new Response(originResponse.body, originResponse);
    response.headers.append(
      'Set-Cookie',
      `app-bucket=${bucket}; Path=/; Max-Age=3600; SameSite=Lax`
    );
    return response;
  },
};
