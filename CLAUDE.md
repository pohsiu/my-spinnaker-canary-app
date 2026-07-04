# CLAUDE.md

## What this repo is

A reference implementation of progressive delivery: a web app (Vite + React
frontend, Express backend) deployed via Helm, promoted through a Spinnaker
Pipeline-as-Code (Dinghy) pipeline with Kayenta canary analysis. Not a
production service — a runnable teaching example. See `site/index.html`
(published to https://pohsiu.github.io/my-spinnaker-canary-app/) for the
full architecture write-up before making structural changes.

## Layout

```
apps/frontend/   Vite + React SPA — dev on :5173 (HMR), builds to dist/
apps/backend/    Express — /api/*, /metrics (Prometheus), serves dist/ in prod
helm/            single Chart, track ∈ {production, canary, baseline} via --set
spinnaker/       dinghyfile (pipeline) + canary-config.json (Kayenta metrics)
site/            architecture doc, deployed via .github/workflows/pages.yml
others/minnaker/ disposable Spinnaker+Kayenta via docker-compose, for testing spinnaker/* locally
```

## Commands

```
npm install
npm run dev                          # turbo: Vite :5173 + Express :3000, proxied
npm run build --workspace=frontend
npm start                            # Express serves apps/frontend/dist
docker build -f apps/backend/Dockerfile -t my-spinnaker-canary-app .   # from repo root
helm lint helm/
helm template test helm/ --set track=canary --set image.tag=<tag>
```

## Conventions

- Node 24+ (`engines` in root `package.json`). Docker images pinned to
  `node:24-alpine`.
- Backend routes live under `/api/*`; anything else falls back to the SPA's
  `index.html` (client-side routing). Don't add top-level routes outside
  `/api` and `/metrics` on the backend.
- Helm track separation (`.Values.track`) drives resource *names* and
  *selector labels* — this is what lets production/canary/baseline coexist
  in the same namespace without collision. Any new template must keep using
  `{{ .Release.Name }}-{{ .Values.track }}` and the `track` label, not a
  fixed name.
- `helm/values.yaml` `image.repository`, `spinnaker/dinghyfile`
  `triggers[].repository`, and `metricsAccountName` in both
  `dinghyfile`/`canary-config.json` are intentionally still placeholders —
  don't "fix" them without a real registry/Spinnaker account to point at.

## GitHub Pages — known trap

Pages is deployed via `.github/workflows/pages.yml` (official
`actions/upload-pages-artifact` + `actions/deploy-pages`, source = `site/`).
Settings → Pages → Source must be **"GitHub Actions"**, not "Deploy from a
branch". We tried the legacy branch-based approach first (orphan `gh-pages`
branch) and its deploy step got stuck `in_progress` indefinitely and never
recovered, even after resaving the branch setting — switched to the Actions
workflow instead, which deploys reliably. The `gh-pages` branch is stale and
unused now; safe to ignore or delete.

## Environment limits when working on this repo

Disk space and Docker daemon availability are **not** fixed constraints —
they were observed low/unavailable in some sessions and fine in others.
Always recheck rather than assuming either state:

```
df -h /            # disk free
docker info         # daemon up?
```

As of the `integrate-local-spinnaker` change, `others/minnaker/` has been
run for real against a live Docker daemon with ample disk — not just
verified structurally. See `others/minnaker/README.md`'s "Local registry,
app deployment, and Kayenta canary analysis" section for what's now
actually been exercised end-to-end (local registry, three-track Helm
deploy, Prometheus scrape, and a real Kayenta canary judgement with both a
passing and a failing run) versus what's still a known limitation (the
Orca `kayentaCanary` pipeline stage itself, as opposed to Kayenta's own
API, has a reproducible bug in this bundled Spinnaker version — see that
README section before assuming the full `spinnaker/dinghyfile` pipeline
runs end-to-end unattended).

If a future session finds Docker unavailable or disk critically low
again, treat that as the current session's environment, not a permanent
property of this machine — note it, and fall back to structural
verification (`kubectl kustomize`, `docker compose config`, `helm
lint`/`helm template`) the way earlier sessions did.
