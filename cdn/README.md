# CDN deployment: `apps/frontend` + `apps/micro-frontend`

Both SPAs are static output (`vite build`) and deploy independently to
**Cloudflare Pages + Workers**, outside the Helm/k8s/Kayenta pipeline that
`spinnaker/dinghyfile` runs for the backend. See `site/index.html` for how
this fits into the overall architecture, and
[`../README.md`](../README.md#micro-frontend-cdn-deployment) for the
build/dev-time picture (Module Federation, `remoteEntry.js`).

**This has been deployed and verified end-to-end against a real Cloudflare
account** (free plan, no credit card) — not just a design on paper anymore.
Both Pages projects, the Workers KV namespace, and both canary-router
Workers exist and are live:

| Resource | Value |
| --- | --- |
| Pages project (frontend) | `my-spinnaker-canary-app-frontend` |
| Pages project (micro-frontend) | `my-spinnaker-canary-app-micro-frontend` |
| Workers KV namespace | `01294afbdf4f44f6bb91287fce76f76d` |
| workers.dev subdomain | `spinnaker-sub` |
| Frontend router | `my-spinnaker-canary-app-frontend-router.spinnaker-sub.workers.dev` |
| Micro-frontend router | `my-spinnaker-canary-app-micro-frontend-router.spinnaker-sub.workers.dev` |

Verified live (Playwright against the real URLs, not local servers):
the host loads `remoteEntry.js` through the micro-frontend router and
renders the widget; the router sets the sticky `app-bucket` cookie; shifting
`micro-frontend.canaryWeight` to 100% in KV made a fresh visitor see a
canary-labeled build, and setting it back to 0% reverted fresh visitors to
stable — both confirmed by an actual page load, not just a KV read.

What's *not* yet real: a custom domain (currently using the shared
`workers.dev` subdomain, since `[[routes]]` needs a zone — see the commented
block in `wrangler.*.toml`), and `cdn/scripts/*.sh` haven't been run
literally as written (testing used `wrangler`/KV commands directly, since
this session is OAuth-authenticated and the scripts intentionally require
`CLOUDFLARE_API_TOKEN` for non-interactive CI use — same shape, not
separately exercised).

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
(invalidate). `invalidate.sh` needs a zone (custom domain) to purge — not
applicable yet while running on the shared `workers.dev` subdomain, which
has no cache to purge in the same sense.

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

`apps/frontend`'s host build needs `MF_REMOTE_URL` pointed at the
**micro-frontend router**, not a specific Pages deployment URL — this was a
real bug caught during live testing: pointing it at a fixed deployment
bakes that exact version into the host bundle, so shifting
`micro-frontend.canaryWeight` in KV has *no effect* on what the host loads.
Only routing through the Worker lets the host observe canary shifts:

```
MF_REMOTE_URL=https://my-spinnaker-canary-app-micro-frontend-router.spinnaker-sub.workers.dev/assets/remoteEntry.js \
  npm run build --workspace=frontend
```

The two pipelines are still independent, but a micro-frontend canary that
changes its exposed API shape is a breaking change for whatever host
version is live regardless of routing — coordinate manually until there's a
contract test between them.

## Redeploying / trying this yourself

Already logged in for this account (`npx wrangler login`, browser OAuth).
To ship a new version by hand (what the Spinnaker pipeline automates):

```
npm run build --workspace=micro-frontend
npx wrangler pages deploy apps/micro-frontend/dist \
  --project-name=my-spinnaker-canary-app-micro-frontend --branch=<sha>
# copy the deployment URL it prints, then:
npx wrangler kv key put "micro-frontend.canaryUrl" "<deployment-url>" \
  --namespace-id 01294afbdf4f44f6bb91287fce76f76d --remote
npx wrangler kv key put "micro-frontend.canaryWeight" "10" \
  --namespace-id 01294afbdf4f44f6bb91287fce76f76d --remote
# verify the canary slice, then promote:
npx wrangler kv key put "micro-frontend.stableUrl" "<deployment-url>" \
  --namespace-id 01294afbdf4f44f6bb91287fce76f76d --remote
npx wrangler kv key put "micro-frontend.canaryWeight" "0" \
  --namespace-id 01294afbdf4f44f6bb91287fce76f76d --remote
```

Same shape for `apps/frontend`, substituting `frontend` for `micro-frontend`
throughout and rebuilding with the `MF_REMOTE_URL` above first.
