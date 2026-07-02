# my-spinnaker-canary-app

Demo project showing a web app (Vite + React frontend, Express backend) deployed
via Helm and progressively rolled out with a Spinnaker + Kayenta canary pipeline.

```
apps/frontend/   # Vite + React SPA (dev hot server / prod static bundle)
apps/backend/    # Express API + Prometheus metrics; serves the built SPA in prod
helm/            # Helm chart (production/baseline/canary via .Values.track)
spinnaker/       # Dinghyfile pipeline-as-code + Kayenta canary metric config
turbo.json       # Turborepo task pipeline (dev/build/lint across apps)
```

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

## Docker

Build from the **repo root** (the Dockerfile needs the whole workspace to
build the frontend, then packages only the backend + built assets into the
final image):

```
docker build -f apps/backend/Dockerfile -t my-spinnaker-canary-app .
```
