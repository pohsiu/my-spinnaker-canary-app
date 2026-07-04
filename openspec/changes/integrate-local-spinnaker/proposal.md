## Why

`others/minnaker/` stands up a real, healthy Spinnaker + Kayenta control plane locally, and `spinnaker/dinghyfile` + `spinnaker/canary-config.json` define a real canary pipeline — but the two have never been connected. The `minnaker-docker-compose` spec explicitly documents this as out of scope: no registry the cluster can pull `apps/backend`'s image from, no Prometheus scrape target on the actual app, and the pipeline itself has never executed a single stage. The core value of this repo (a working canary-analysis pipeline) is currently unverified end to end. The host constraint that previously blocked even running `others/minnaker/` (low disk space) no longer holds — 206GB is now free and the Docker daemon is up — so this gap is closeable now.

## What Changes

- Add a throwaway local container registry (`registry:2`) that both the host Docker daemon and the minnaker-managed k3s cluster can reach, so `apps/backend`'s image is pullable in-cluster without a real Docker Hub account.
- Deploy `apps/backend` via `helm/` into the minnaker cluster across all three tracks (`production`, `canary`, `baseline`), replacing `spinnaker/dinghyfile`'s and `spinnaker/canary-config.json`'s placeholder registry/account values with values that resolve against this local stack.
- Wire the in-cluster Prometheus (already installed by `others/minnaker/manifests`) to actually scrape the deployed pods' `/metrics`, so Kayenta's canary analysis has real time series to query instead of an empty metrics account.
- Apply `spinnaker/dinghyfile`'s rendered pipeline JSON to Gate directly (manual `curl`, matching the already-verified access path in `others/minnaker/README.md`) — no Dinghy git-sync install in this change.
- Execute the full pipeline at least twice: once with a healthy canary (expect promote to production) and once with a deliberately degraded canary (expect Kayenta to fail the analysis and block promotion) — proving the `canaryAnalysis` stage actually discriminates, not just that the pipeline completes.
- Update `others/minnaker/README.md`'s "What this does NOT do" section to reflect what is now actually exercised, and correct the "Environment limits" note in root `CLAUDE.md` (disk space, Docker daemon availability) which is now stale.

## Capabilities

### New Capabilities
- `local-pipeline-e2e-validation`: end-to-end execution of `spinnaker/dinghyfile` against a live local Spinnaker/Kayenta instance and a real deployed `apps/backend`, covering image delivery (local registry), multi-track Helm deployment, Prometheus scrape wiring, manual pipeline application via Gate, and both a passing and a failing canary run.

### Modified Capabilities
- `minnaker-docker-compose`: the "Documented scope boundary" requirement changes — the stack no longer stops at "control plane only." The registry and Prometheus-scrape-target gaps it currently documents as prerequisites are closed by this change, so the boundary statement in `others/minnaker/README.md` needs to move to reflect what's newly in scope vs. what's still out of scope (e.g. Dinghy git-sync remains unimplemented).

## Impact

- `others/minnaker/docker-compose.yml` and `others/minnaker/manifests/`: add a registry service and Prometheus scrape config; likely a new patch file for scrape targets.
- `helm/values.yaml`, `spinnaker/dinghyfile`, `spinnaker/canary-config.json`: placeholder `image.repository`, `triggers[].repository`, and `metricsAccountName` values become concrete, pointed at the local stack (CLAUDE.md's existing note against "fixing" these without a real target to point at no longer applies once that target is this local stack).
- `apps/backend`: no code changes expected; its existing `/metrics` endpoint is the scrape target.
- `others/minnaker/README.md`, root `CLAUDE.md`: documentation updates reflecting newly-verified capability and corrected environment constraints.
- No production systems affected — this is entirely local, disposable infrastructure (`docker compose down -v` still returns the host to a clean state).
