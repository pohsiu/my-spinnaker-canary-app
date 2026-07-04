## Context

`others/minnaker/` (see `openspec/specs/minnaker-docker-compose/spec.md`) already brings up a verified-healthy Spinnaker + Kayenta control plane on k3s-in-Docker, with an in-cluster Prometheus installed (via `spinnaker-kustomize-patches/infrastructure/prometheus-grafana`) but not scraping anything real, and a Kayenta Prometheus metrics account registered but never queried. `helm/` renders a working chart (`helm lint` / `helm template` verified) but has never been `helm install`ed anywhere. `spinnaker/dinghyfile` and `spinnaker/canary-config.json` are well-formed pipeline/canary-config JSON that has never been submitted to Gate. The three pieces are individually validated; nothing connects them.

Constraints carried over from `others/minnaker/README.md`:
- k3s runs `--disable=traefik`; the only host access path is the `port-forward` sidecar's `kubectl port-forward` on 8084/9000. Anything new (registry, scrape targets) has to work within or alongside that, not assume ingress.
- The Operator's `SpinnakerService.spec.spinnakerConfig.config` is `x-kubernetes-preserve-unknown-fields: true` and array fields (`serviceIntegrations`, etc.) replace wholesale on patch — already burned once by this in `patch-canary-storage.yml`. Any new patch touching `serviceIntegrations` must edit that existing file, not add a second one.
- No Dinghy install exists or is being added in this change (explicit non-goal below) — Gate's pipeline-save API is the only way pipelines get created.
- Root `CLAUDE.md` currently documents this environment as unable to run `others/minnaker/` at all (disk space) — confirmed stale during exploration (206GB free, Docker daemon up as of 2026-07-03), but that note needs correcting as part of this change so future sessions don't rediscover the same wrong assumption.

## Goals / Non-Goals

**Goals:**
- Get a real image of `apps/backend`, built from this repo, running inside the minnaker-managed k3s cluster under all three Helm tracks (`production`, `canary`, `baseline`).
- Get the in-cluster Prometheus actually scraping those pods' `/metrics`.
- Submit `spinnaker/dinghyfile`'s pipeline to Gate and execute it for real, end to end: bake → deploy canary+baseline → Kayenta analysis → promote.
- Prove the Kayenta stage discriminates — one run against a healthy canary (passes, promotes) and one against a deliberately degraded canary (fails, blocks promotion) — not just that stages execute without erroring.
- Leave the whole thing disposable: `docker compose down -v` still returns the host to a clean state; nothing here depends on real external credentials.

**Non-Goals:**
- Installing Dinghy for git-triggered pipeline sync. Manual `curl` to Gate's pipeline-save endpoint is sufficient to prove the pipeline logic works; git-sync is a separate, heavier concern.
- Pushing to a real Docker Hub account. `dinghyfile`'s `triggers[].repository` placeholder stays a placeholder for the *real* CI case; this change points the pipeline at the local registry instead, which is a different, additive configuration path, not a resolution of that placeholder.
- CI automation (GitHub Actions triggering this flow). This is a manually-run local validation loop.
- Any change to `apps/backend` application code. `/metrics` already exists (`apps/backend/server.js`, `prom-client`, standard Prometheus text format) and needs no modification.

## Decisions

**Local registry: a `registry:2` container on the compose network, not a real Docker Hub repo.**
Keeps the whole loop disposable and credential-free, matching `others/minnaker`'s existing philosophy. The registry needs to be reachable both from the host (`docker build`/`push`) and from k3s (image pulls) — simplest path is adding `registry` as a compose service on the same network as `k3s`, then configuring k3s's containerd to treat it as insecure/HTTP (k3s's `registries.yaml` mechanism), since standing up TLS for a throwaway registry is unwarranted complexity. Alternative considered: `k3s ctr images import` to sideload the image without any registry at all — rejected because it doesn't exercise the `dinghyfile` trigger's actual pull-based deploy path, which is the thing being validated.

**Pipeline submission: manual `curl` to Gate's `/pipelines` save endpoint.**
`others/minnaker/README.md` already documents this as the tested access path (Gate reachable and authenticated at `localhost:8084`). Installing Dinghy is real additional surface (another service, another failure mode) for a capability (git-sync) this change doesn't need to prove. Rendering `dinghyfile`'s Jinja-esque `${trigger.tag}` templating without Dinghy means the pipeline JSON gets submitted with concrete stage config directly — `dinghyfile`'s own trigger/stage structure is preserved, just applied as a literal `POST` instead of via git-sync.

**Prometheus scrape config: a new/edited patch in `others/minnaker/manifests/`, not a Helm-chart-embedded ServiceMonitor.**
The in-cluster Prometheus here is upstream minnaker's plain `prometheus-grafana` recipe, not a Prometheus Operator install — no `ServiceMonitor` CRD exists to target. Scrape config has to be a static `scrape_configs` entry (or `kubernetes_sd_configs` role: pod with relabeling on a `track` label) added via a kustomize patch to Prometheus's ConfigMap, consistent with how every other minnaker customization here is already done.

**Track image tags: reuse the same image for canary/baseline in the "healthy" run; build a second, deliberately-degraded image for the "failing" run.**
The chart's `image.tag` already varies per track via `--set image.tag=`. For the pass case, canary and baseline get the same tag as production (proving Kayenta correctly finds no meaningful diff). For the fail case, canary's tag points at a build with an intentionally injected fault (e.g., an endpoint modified to elevate `5xx` rate or latency) — this proves the `HTTP 5xx Error Rate` / `HTTP p95 Latency` metrics in `canary-config.json` actually drive the `scoreThresholds`. The exact fault mechanism (env var toggle vs. a throwaway code branch vs. injected via a sidecar) is an open question below.

**CLAUDE.md correction is in-scope, not a follow-up.**
The stale "Environment limits" section actively misleads future sessions into believing this work is blocked. Since this change's own execution depends on that constraint being false, correcting it here (rather than as a separate change) keeps the documentation and the evidence that contradicts it together.

## Risks / Trade-offs

- **[Risk]** k3s trusting an insecure/HTTP local registry may need containerd config that's awkward to inject post-hoc into an already-running k3s server container (`registries.yaml` is normally read at k3s startup). → **Mitigation**: mount `registries.yaml` into the `k3s` service in `docker-compose.yml` before first boot, rather than trying to patch a running node; document if a full `docker compose down -v` + `up` cycle is required for this to take effect.
- **[Risk]** Kustomize's wholesale-replace behavior on `serviceIntegrations` (already known from `patch-canary-storage.yml`) means any Prometheus scrape-config patch touching the same array must be merged into the existing patch file, not layered — easy to accidentally clobber the existing `aws`/Minio config store integration. → **Mitigation**: scrape config lives in Prometheus's own ConfigMap (a separate resource from `SpinnakerService`), so it's a new/independent patch target, not a conflict with `patch-canary-storage.yml` at all — confirmed during design, not just assumed.
- **[Risk]** The "degraded canary" fault injection could be too subtle (Kayenta doesn't fail) or too crude (fails for an uninteresting reason, e.g. crash-loop instead of a real metric regression). → **Mitigation**: prefer a runtime-configurable fault (env var read at request time, e.g. `FAULT_INJECT_5XX_RATE`) over a separate code branch, so the same image can be reused for both good and bad runs and the fault's magnitude is tunable without a rebuild.
- **[Risk]** `lifetimeDuration: PT30M` in `dinghyfile`'s canary stage means each full pipeline run takes up to 30 minutes — two runs (pass + fail) is a slow feedback loop for iterating on the setup itself. → **Mitigation**: consider a temporarily shortened duration (e.g. `PT5M`) for validation runs, reverting to `PT30M` before this change merges, since the shorter window is a debugging convenience, not the documented/intended behavior.
- **[Trade-off]** Skipping Dinghy means the validated pipeline-application path (manual Gate POST) differs from how a real deployment would trigger it (git-sync on `dinghyfile` commit). This change proves the pipeline *logic*, not the git-integration path — acceptable given the non-goal above, but worth stating so it isn't mistaken for full CI coverage.

## Migration Plan

This is net-new local-only tooling; there's no production migration. Sequencing within the change:
1. Local registry + k3s trust config (foundational — nothing else can deploy without it).
2. Build and push `apps/backend` image to the local registry.
3. `helm install`/`upgrade` all three tracks into the minnaker cluster manually first (bypassing Spinnaker) to prove the chart + registry + cluster combination works in isolation, before adding pipeline orchestration on top.
4. Prometheus scrape config patch, confirmed via Kayenta's own query path (not just `curl` to Prometheus directly).
5. Submit `dinghyfile` to Gate, trigger a run manually, observe the healthy-canary pass case.
6. Build the degraded image, trigger a second run, observe the Kayenta failure case.
7. Update `others/minnaker/README.md` and root `CLAUDE.md` once both runs are confirmed.

Rollback is `docker compose down -v` (destroys everything) — no partial-state cleanup concerns since nothing here persists outside that compose project's volumes.

## Open Questions

- Fault-injection mechanism for the degraded canary image: env-var-gated fault in `apps/backend/server.js` vs. a separate throwaway Docker tag with hardcoded bad behavior? (Design leans env-var; needs confirmation before `tasks.md` locks it in.)
- Does the local registry need a second host-side port-forward/mapping, or is host-side `docker push` sufficient via the compose network's published port alone?
- Should the shortened `lifetimeDuration` (`PT5M`) live as a temporary local override applied only when POSTing to Gate manually, to avoid ever touching the committed `dinghyfile` value?
