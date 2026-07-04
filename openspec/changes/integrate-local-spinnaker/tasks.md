## 1. Local registry + cluster trust

- [x] 1.1 Add a `registry:2` service to `others/minnaker/docker-compose.yml` on the same compose network as `k3s`
- [x] 1.2 Configure k3s's containerd to trust the registry as an insecure/HTTP mirror (mount a `registries.yaml` into the `k3s` service, applied at container start)
- [x] 1.3 Recreate the `k3s` service to confirm the registry trust config takes effect (verified via a real container recreate, not a full `down -v` — named volumes preserved node state; required manually relabeling the node and rescheduling pods pinned to the old node identity, documented as a new known issue)
- [x] 1.4 Build `apps/backend`'s image from repo root and push it to the local registry from the host; confirm no TLS/credential errors (hit a real macOS AirPlay Receiver conflict on host port 5000 — remapped to 5050, documented)

## 2. Manual Helm deploy (bypassing Spinnaker)

- [x] 2.1 Use `--set image.repository=registry:5000/my-web-service` at `helm template`/deploy time rather than editing `helm/values.yaml` — keeps the committed placeholder generic for readers without this local stack
- [x] 2.2 Apply the `production` track into the minnaker cluster (`helm template` + `kubectl apply`, since the k8s API isn't host-reachable — only Gate/Deck are published); confirm pod Running and image pulled from the local registry (confirmed via `imageID` digest match)
- [x] 2.3 Repeat for `canary` and `baseline` tracks with the same image tag; confirm all three coexist without name/selector collisions (9/9 pods Running immediately)
- [x] 2.4 `curl` each track's pod directly to confirm the app serves traffic (200) and `/metrics` responds

## 3. Prometheus scrape wiring

- [x] 3.1 ~~Add a kustomize patch...~~ **Not needed** — discovered the upstream recipe's Prometheus config already has a `kubernetes-pods` job with generic `prometheus.io/scrape` annotation-based discovery, and `helm/templates/deployment.yaml` already sets those annotations. No new patch required; design.md's proposed patch was unnecessary.
- [x] 3.2 Confirmed via Prometheus's `/api/v1/targets`: all 9 app pods discovered under `job=kubernetes-pods`, `health:"up"`, `track` label preserved
- [x] 3.3 Generated real traffic (60 req/track against `/api/hello`, the only instrumented endpoint) and confirmed non-empty `sum(http_requests_total) by (track)` and p95 latency queries for all three tracks
- [x] 3.4 Confirmed via Kayenta's own `/credentials` endpoint: a `prometheus` account (`METRICS_STORE`, `baseUrl: http://prometheus.spinnaker:9090`) is registered and Kayenta's overall health is `UP`. **Note for task 5**: this account is named `prometheus`, not `my-prometheus-account` as `spinnaker/dinghyfile` currently references — needs resolving at pipeline-submission time.

## 4. Fault-injection support for the degraded canary case

- [x] 4.1 Added `FAULT_INJECT_5XX_RATE` and `FAULT_INJECT_LATENCY_MS` env vars to `apps/backend/server.js`, additive on top of the existing baseline 2% error rate
- [x] 4.2 Rebuilt/pushed (new digest `sha256:6cf5ec...`), rolled out via `imagePullPolicy: Always` patch + restart (tag `stable` was cached, needed to force repull), confirmed inert by default (20/20 requests `200` with no env var set) — single image/tag used for both fault-on and fault-off; the env var (set via `--set env` at deploy time in task 5) distinguishes the cases instead of a second tag

## 5. Pipeline submission and execution

- [x] 5.1 Built a `Helm-Canary-Deploy-Pipeline` (bake canary/baseline via embedded/base64 Helm chart artifacts → deploy → analysis → bake/deploy production) and submitted it to Gate at `/api/pipelines` (note: root path needs `/api` prefix per `patch-local-access.yml`). Bake and Deploy stages (canary + baseline) verified working end-to-end against the local registry and minnaker cluster.
- [x] 5.2 Confirmed persisted/triggerable via Gate's manual-execution endpoint (`POST /api/pipelines/my-web-service/Helm-Canary-Deploy-Pipeline`)
- [x] 5.3 Used `lifetimeDuration: PT5M` (and later a 2-minute analysis window for the standalone-API runs) for fast iteration, per design's open question
- [x] 5.4/5.5 **Superseded by a better outcome than originally planned.** The Orca `kayentaCanary` stage type has a real, unresolved bug in this bundled Spinnaker version (`Unable to map context to class ...KayentaCanaryContext`; root-cause investigation — bytecode decompilation, live actuator introspection, standalone-harness reproduction inside the running pod — never found the cause; documented in `others/minnaker/README.md`). Initially worked around by calling Kayenta's standalone API directly and bypassing the pipeline entirely. **Then went further**: redesigned `spinnaker/dinghyfile` to replace the single broken `canaryAnalysis`/`kayentaCanary` stage with `evaluateVariables` (compute analysis window) → `runJob` (generate traffic) → `webhook`×2 (start + poll the Kayenta judgement directly) → `checkPreconditions` (gate promotion on the real classification) — so the **full pipeline now runs end-to-end through Gate**, not just the judgement logic in isolation.
  - **Healthy run, triggered via Gate, full pipeline**: all 11 stages `SUCCEEDED` including `Bake Production`/`Promote to Production`, judge score **100, Pass**
  - **Degraded runs** (two, before the histogram-bucket fix below): `Check Canary Score` correctly failed the pipeline before `Bake Production` ran, both times — proves the promotion gate is real, not just cosmetic
  - Two new bugs found implementing the webhook-stage design (documented in README): the poll stage's `statusJsonPath` must target an always-present field (`$.status`), not one absent until completion (Orca's `MonitorWebhookTask` treats an unresolvable JsonPath as `TERMINAL`, not "keep polling"); and the actual final poll response lives at `context.webhook.monitor.body`, not `context.webhook.body` (a stale initial-POST snapshot)
  - Also found and fixed two real, separate issues surfaced only by running this repeatedly: `apps/backend/server.js`'s Prometheus histogram buckets were too coarse for the app's actual 0–200ms latency range, causing spurious `Fail` classifications on identical canary/baseline images (fixed: finer buckets); and `deployManifest` re-applying an unchanged `image:tag` string doesn't make Kubernetes repull/restart pods, so code changes silently didn't take effect across pipeline runs (fixed: `imagePullPolicy: Always` added to `helm/templates/deployment.yaml`)
  - Earlier standalone-API findings still apply and remain in the design: `canary-config.json`'s `customFilter` is deprecated (use `customInlineTemplate` with a `PromQL:` prefix), the 5xx-rate query needs `sum(...) or vector(0)` to avoid false `NODATA`, and the real account names are `spinnaker`/`prometheus` (not the dinghyfile's original placeholders)

## 6. Documentation cleanup

- [x] 6.1 Updated `others/minnaker/README.md`: trimmed "What this does NOT do" to what's still actually out of scope, added a new section covering the local registry, Helm deploy, Prometheus scrape, and Kayenta findings, plus a "Known limitation" subsection for the Orca `kayentaCanary` stage bug
- [x] 6.2 Corrected root `CLAUDE.md`'s environment-limits section — reframed disk/Docker as re-checkable per-session state rather than a fixed constraint, pointed at the new README section
- [x] 6.3 Evidence recorded inline in `others/minnaker/README.md`'s new section: Kayenta canary execution IDs are in this change's session log; scores (100/Pass healthy, 50/Fail degraded) and the specific metric classifications are documented there directly
