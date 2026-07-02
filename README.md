# my-spinnaker-canary-app

Demo project showing a web app (Vite + React frontend, Express backend) deployed
via Helm and progressively rolled out with a Spinnaker + Kayenta canary pipeline.

```
apps/frontend/   # Vite + React SPA (dev hot server / prod static bundle)
apps/backend/    # Express API + Prometheus metrics; serves the built SPA in prod
helm/            # Helm chart (production/baseline/canary via .Values.track)
spinnaker/       # Dinghyfile pipeline-as-code + Kayenta canary metric config
site/            # Architecture/flow write-up, published via GitHub Pages
turbo.json       # Turborepo task pipeline (dev/build/lint across apps)
```

Architecture write-up: https://pohsiu.github.io/my-spinnaker-canary-app/ (deployed
by `.github/workflows/pages.yml` on every push to `main` that touches `site/`)

## Prerequisites

- Node.js 24+
- Docker (only needed for building the container image)
- A Kubernetes cluster + Spinnaker/Kayenta install (only needed for the canary
  pipeline; not required for local development)

## Develop

```
npm install
npm run dev
```

Runs both apps via Turborepo: Vite dev server on `:5173` (with HMR) proxying
`/api` and `/metrics` to the Express backend on `:3000`.

## Production build

```
npm run build --workspace=frontend
npm start
```

`npm start` runs the Express backend, which serves the built SPA from
`apps/frontend/dist` on `:3000` (any non-`/api`, non-`/metrics` route falls
back to `index.html` for client-side routing), alongside `/api/hello` and
`/metrics`.

## API endpoints (backend)

| Route         | Description                                      |
| ------------- | ------------------------------------------------- |
| `GET /api/hello` | Demo endpoint; ~2% random 500s to exercise canary failure detection |
| `GET /metrics`   | Prometheus metrics (request count/duration, default Node process metrics) |
| `GET /*`         | Falls back to the built SPA (`index.html`) in production |

## Docker

Build from the **repo root** (the Dockerfile needs the whole workspace to
build the frontend, then packages only the backend + built assets into the
final image):

```
docker build -f apps/backend/Dockerfile -t my-spinnaker-canary-app .
```

> Not yet verified against a running Docker daemon in this environment —
> confirm the build succeeds before relying on it in CI.

## Deploying via Helm + Spinnaker

`helm/` and `spinnaker/` are still templated with placeholder values —
fill these in for your environment before wiring up the pipeline:

- `helm/values.yaml`: `image.repository` — your real container registry path
- `spinnaker/dinghyfile`: `triggers[].repository` — same registry path as above
- `spinnaker/canary-config.json` / `dinghyfile`: `metricsAccountName` /
  `my-prometheus-account` — your Spinnaker Prometheus account name

The pipeline (`spinnaker/dinghyfile`) bakes the Helm chart with
`track: canary`, runs Kayenta analysis against the `HTTP 5xx Error Rate` and
`HTTP p95 Latency` metrics defined in `spinnaker/canary-config.json`, and on a
passing score (≥90) promotes the release with `track: production`.
