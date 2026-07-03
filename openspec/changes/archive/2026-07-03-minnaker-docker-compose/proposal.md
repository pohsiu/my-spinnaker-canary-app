## Why

There is no way to exercise `spinnaker/dinghyfile` and `spinnaker/canary-config.json` against a real Spinnaker + Kayenta install anywhere in this repo or its docs — `helm lint`/`helm template` verify the Helm chart in isolation, but the bake → Kayenta analysis → promote pipeline itself has never run. [Minnaker](https://github.com/armory/minnaker) is the lowest-friction way to stand up a real Spinnaker instance, but it's designed as a bare-VM installer (installs k3s, MySQL, Redis, Minio directly on the host via a root shell script), which doesn't fit a repo that otherwise runs everything through Docker/Compose. Packaging an equivalent stack as `docker-compose` lets a contributor run `docker compose up` locally (or on any Docker host) to get a disposable Spinnaker instance to test this repo's pipelines against, without provisioning a dedicated VM.

## What Changes

- Add `others/minnaker/docker-compose.yml`: a k3s-in-Docker cluster (`rancher/k3s` server, privileged) plus a one-shot bootstrap container that installs the Spinnaker Operator, then `kubectl apply -k`s minnaker's actual upstream recipe (fetched directly from a pinned commit of `armory/spinnaker-kustomize-patches` via kustomize's remote-base support — not vendored), reproducing minnaker's stack inside containers instead of a bare VM.
- Add `others/minnaker/manifests/kustomization.yml`: a small local kustomization referencing that pinned upstream recipe as a remote base, plus minnaker's own (upstream-provided but disabled-by-default) Kayenta/Prometheus resources, plus one local patch file correcting the Prometheus account's `baseUrl` to point at the in-cluster Prometheus service.
- Add `others/minnaker/README.md`: what this is, how it differs from minnaker's bare-VM install, resource requirements, how to point it at this repo's `spinnaker/dinghyfile` and `spinnaker/canary-config.json`, and how to tear it down.
- **Not building**: a Prometheus target wired to `apps/backend`'s `/metrics`, or a container registry for the `dinghyfile`'s Docker trigger — those placeholders (documented in `README.md` and `CLAUDE.md`) still need real values before an end-to-end canary run works against this repo's actual app; this change only stands up the Spinnaker/Kayenta control plane itself.

## Capabilities

### New Capabilities
- `minnaker-docker-compose`: a Docker Compose–packaged, disposable Spinnaker + Kayenta instance (k3s-in-Docker + Spinnaker Operator) for locally testing this repo's pipeline-as-code files, living under `others/minnaker/`.

### Modified Capabilities
(none — no existing specs in this repo yet)

## Impact

- **New top-level directory** `others/minnaker/` (docker-compose.yml, manifests, README) — no changes to `apps/`, `helm/`, `spinnaker/`, or `cdn/`.
- **Local resource requirements**: matches minnaker's own minimums (4 vCPU / 16GB RAM / 30GB disk) since it's the same stack, just containerized — this repo's current dev machine has only ~11GB free disk, which is a known blocker to actually *running* this stack there, not to building it. Flagged in the new README rather than worked around.
- **No CI/CD wiring**: this is a local testing aid, not part of `.github/workflows/`. Nothing in the existing Turborepo `dev`/`build` pipeline changes.
- **Docker Desktop / a Docker host with privileged-container support required** — k3s-in-Docker needs `--privileged`, which some restricted Docker setups (e.g. some CI runners, rootless Docker) disallow. Documented as a prerequisite.
