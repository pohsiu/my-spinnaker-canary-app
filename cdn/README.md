# CDN deployment: `apps/frontend` + `apps/micro-frontend`

Both SPAs are static output (`vite build`) and deploy independently to
**S3 + CloudFront**, outside the Helm/k8s/Kayenta pipeline that
`spinnaker/dinghyfile` runs for the backend. See `site/index.html` for how
this fits into the overall architecture, and
[`../README.md`](../README.md#micro-frontend-cdn-deployment) for the
build/dev-time picture (Module Federation, `remoteEntry.js`).

This is a **design + reference implementation**, not a deployed environment
— nothing here has run against a real AWS account. Placeholders
(`<CDN_BUCKET>`, `<CLOUDFRONT_KVS_ARN>`, `<CLOUDFRONT_DISTRIBUTION_ID>`) need
real values, same spirit as the existing Helm/Spinnaker placeholders.

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

## Bucket layout

```
s3://<CDN_BUCKET>/
  frontend/releases/<git-sha>/...        # immutable, one folder per build
  micro-frontend/releases/<git-sha>/...
```

Nothing under `releases/` is ever mutated or deleted by a deploy — old
versions stay put until manually cleaned up, so rollback is just pointing
the manifest at an older SHA.

## Routing: CloudFront Functions + KeyValueStore

Two CloudFront Functions (`cdn/edge/viewer-request.js`,
`viewer-response.js`) decide, per request, whether a visitor sees `stable`
or `canary`, sticky via a cookie so a page's HTML and its JS/CSS chunks
never come from different versions. Chosen over Lambda@Edge for lower
latency/cost — this doesn't need Lambda's compute, just a KV lookup.

Each app gets its **own instance** of the same function, published with its
name substituted in:

```
sed "s/__APP_NAME__/frontend/" cdn/edge/viewer-request.js > /tmp/frontend-viewer-request.js
# publish /tmp/frontend-viewer-request.js as the "frontend-viewer-request" CloudFront Function
# repeat with APP_NAME=micro-frontend
```

KVS keys, namespaced per app in one shared store:

| Key | Meaning |
| --- | --- |
| `<app>.stableVersion` | version served to the non-canary majority |
| `<app>.canaryVersion` | version served to the canary slice |
| `<app>.canaryWeight` | 0–100, percent of *new* visitors routed to canary |

## Deploy scripts (`cdn/scripts/`)

Thin `aws` CLI wrappers, meant to run as Spinnaker **Run Job** stages via
the `cdn/deploy-tools` image (build from repo root:
`docker build -f cdn/deploy-tools/Dockerfile -t cdn-deploy-tools .`):

| Script | Effect |
| --- | --- |
| `deploy-release.sh <app> <version> <dist-dir>` | Uploads a build to `releases/<version>/`. Affects zero live traffic. |
| `shift-canary.sh <app> <version> <weight>` | Points the canary slice at `<version>` and sets its traffic %. |
| `promote.sh <app> <version>` | Cuts `stable` over to `<version>`, zeroes canary weight. This is the traffic-affecting step. |
| `invalidate.sh <app>` | Invalidates cached `index.html` after a promote. |

Required env vars: `CDN_BUCKET`, `CLOUDFRONT_KVS_ARN`,
`CLOUDFRONT_DISTRIBUTION_ID`.

## Pipeline shape

See `spinnaker/frontend-dinghyfile` and
`spinnaker/micro-frontend-dinghyfile` — same five stages for both apps:

1. Build & upload release (`deploy-release.sh`) — no traffic impact
2. Shift canary to 10% (`shift-canary.sh`)
3. Manual Judgment — human checks the canary slice (RUM gate, later)
4. Promote to 100% (`promote.sh`)
5. Invalidate cache (`invalidate.sh`)

`apps/frontend`'s host build needs `MF_REMOTE_URL` pointed at
`apps/micro-frontend`'s **stable** `remoteEntry.js` URL at build time (see
root README) — the two pipelines are independent, but a micro-frontend
canary that changes its exposed API shape is still a breaking change for
whatever host version is live. Coordinate manually until there's a contract
test between them.
