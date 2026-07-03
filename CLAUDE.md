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

No local Kubernetes cluster, no `kubeconform`, and Docker daemon is
typically not running — `helm lint`/`helm template` can be verified, but
rendered manifests can't be schema-validated against a live API server, and
`docker build` has not been exercised end-to-end. Flag this rather than
claiming either is fully verified.

Disk space has also been observed critically low (~11GB free of ~460GB —
run `df -h /` to recheck before assuming otherwise), which blocks actually
running `others/minnaker/` (needs ~30GB). Its manifests, compose file, and
bootstrap script were verified by other means instead — `kubectl kustomize`
(manifest rendering against the real pinned upstream), `docker compose
config` (compose syntax), `shellcheck` (bootstrap script) — not by an
actual `docker compose up`. See `others/minnaker/README.md`'s "What this
does NOT do" section before assuming more was verified than that.
