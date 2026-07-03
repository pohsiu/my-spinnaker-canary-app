# CDN deployment: `apps/frontend` + `apps/micro-frontend`

Both SPAs are static output (`vite build`) and deploy independently to
**Cloudflare Pages + Workers**, outside the Helm/k8s/Kayenta pipeline that
`spinnaker/dinghyfile` runs for the backend. See `site/index.html` for how
this fits into the overall architecture, and
[`../README.md`](../README.md#micro-frontend-cdn-deployment) for the
build/dev-time picture (Module Federation, `remoteEntry.js`).

This is a **design + reference implementation**, not a deployed environment
— nothing here has run against a real Cloudflare account yet. Placeholders
(`<CF_KV_NAMESPACE_ID>`, `<CF_ZONE_ID>`, `<FRONTEND_DOMAIN>`, etc.) need real
values, same spirit as the existing Helm/Spinnaker placeholders. Cloudflare's
free plan covers everything here (Pages: unlimited static requests; Workers:
100k requests/day; Workers KV: 100k reads + 1k writes/day) — no credit card
required to try it.

## Why not Kayenta for these

Kayenta's canary analysis in this repo works because k8s gives us two
comparable Pod groups (`track=canary` vs `track=baseline`) and Prometheus
metrics scoped by that label. A CDN-hosted SPA has neither — there's no pod,
and "is this version healthy" for a frontend is a RUM/Web-Vitals/JS-error
question, not a Prometheus one. This repo has no RUM pipeline yet, so the
frontend pipelines below use a **Manual Judgment** gate instead of an
automated score. Swapping that gate for real RUM-based analysis (e.g.
ingest `web-vitals` + JS error rate into the same Prometheus, add a second
Kayenta config) is the natural next step, not a redesign.

## Why Cloudflare Pages simplifies the "versioned release" problem

The AWS S3 version of this design needed to manually build a
`releases/<git-sha>/` prefix structure to keep old builds addressable.
Cloudflare Pages does this natively: **every `wrangler pages deploy` gets
its own permanent, immutable URL** (`https://<deployment-id>.<project>.pages.dev`),
whether or not it's ever pointed at by production traffic. So:

```
my-spinnaker-canary-app-frontend         (Pages project, one per app)
  ├─ https://a1b2c3d.my-spinnaker-canary-app-frontend.pages.dev   (one URL per deploy)
  ├─ https://e4f5g6h.my-spinnaker-canary-app-frontend.pages.dev
  └─ ...

my-spinnaker-canary-app-micro-frontend
  └─ ...
```

Nothing is ever mutated or deleted by a deploy — rollback is just pointing
the router at an older deployment URL.

## Routing: a Worker in front of two Pages deployments

`cdn/edge/canary-router.js` is a Cloudflare Worker that, per request, picks
`stable` or `canary`, sticky via a cookie, and proxies (`fetch()`) to the
matching Pages deployment URL — so a page's HTML and its JS/CSS chunks never
come from two different deployments. One Worker + one Workers KV lookup per
request; no separate request/response function pair needed (unlike the
CloudFront Functions design this replaced), and no Lambda-style cold start.

Each app gets its **own Worker deployment** from the same
`canary-router.js` source, configured via
`cdn/edge/wrangler.frontend.toml` / `wrangler.micro-frontend.toml`
(`APP_NAME` var + KV binding + route, per app):

```
cd cdn/edge
npx wrangler deploy -c wrangler.frontend.toml
npx wrangler deploy -c wrangler.micro-frontend.toml
```

KV keys, namespaced per app in one shared namespace:

| Key | Meaning |
| --- | --- |
| `<app>.stableUrl` | Pages deployment URL served to the non-canary majority |
| `<app>.canaryUrl` | Pages deployment URL served to the canary slice |
| `<app>.canaryWeight` | 0–100, percent of *new* visitors routed to canary |

## Deploy scripts (`cdn/scripts/`)

Thin `wrangler`/`curl` wrappers, meant to run as Spinnaker **Run Job**
stages via the `cdn/deploy-tools` image (build from repo root:
`docker build -f cdn/deploy-tools/Dockerfile -t cdn-deploy-tools .`):

| Script | Effect |
| --- | --- |
| `deploy-release.sh <app> <version> <dist-dir>` | Creates a new Pages deployment, prints its URL. Affects zero live traffic. |
| `shift-canary.sh <app> <deployment-url> <weight>` | Points the canary slice at `<deployment-url>` and sets its traffic %. |
| `promote.sh <app> <deployment-url>` | Cuts `stable` over to `<deployment-url>`, zeroes canary weight. This is the traffic-affecting step. |
| `invalidate.sh <app>` | Purges Cloudflare's edge cache for the app's custom domain after a promote. |

Required env vars: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`,
`CF_KV_NAMESPACE_ID` (shift/promote), `CF_ZONE_ID` + `APP_DOMAIN`
(invalidate).

## Pipeline shape

See `spinnaker/frontend-dinghyfile` and
`spinnaker/micro-frontend-dinghyfile` — same five stages for both apps:

1. Build & upload release (`deploy-release.sh`) — no traffic impact
2. Shift canary to 10% (`shift-canary.sh`)
3. Manual Judgment — human checks the canary slice (RUM gate, later)
4. Promote to 100% (`promote.sh`)
5. Invalidate edge cache (`invalidate.sh`)

The exact mechanism for passing stage 1's printed deployment URL into
stages 2 and 4 (`${#stage('Build & Upload Release')['outputs']['deploymentUrl']}`
in the dinghyfiles) depends on how Run Job stage output is wired in your
Spinnaker install — flagged there rather than assumed.

`apps/frontend`'s host build needs `MF_REMOTE_URL` pointed at
`apps/micro-frontend`'s **stable** deployment's `remoteEntry.js` URL at
build time (see root README) — the two pipelines are independent, but a
micro-frontend canary that changes its exposed API shape is still a
breaking change for whatever host version is live. Coordinate manually
until there's a contract test between them.

## Trying this for real

Requires a (free) Cloudflare account and logging in locally:

```
npx wrangler login          # browser OAuth
# or set CLOUDFLARE_API_TOKEN for non-interactive use
```

Then: create two Pages projects, one Workers KV namespace, deploy the two
routers with the wrangler.*.toml files above, and fill in every
`<PLACEHOLDER>` in this repo's `cdn/` and `spinnaker/*-dinghyfile` files
with the real IDs `wrangler`/the Cloudflare dashboard gives you.
