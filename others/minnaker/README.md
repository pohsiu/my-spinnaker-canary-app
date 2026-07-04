# Disposable Spinnaker + Kayenta, via Docker Compose

A local, throwaway Spinnaker instance for testing this repo's
`spinnaker/dinghyfile` and `spinnaker/canary-config.json` against a real
install — reproducing what [minnaker](https://github.com/armory/minnaker)
does on a bare VM, but as `docker compose up` instead.

**Status: fully working, verified end-to-end against a real Docker daemon.**
`docker compose up -d` brings up a healthy Spinnaker + Kayenta instance —
Deck and Gate both respond on the host, and Kayenta itself reports healthy
with a working config/object store. See "Current status" below for the
full path to get there (several real upstream bugs fixed along the way)
and what's still explicitly out of scope.

## Prerequisites

- Docker with **privileged-container support** (k3s-in-Docker needs
  `--privileged`; this will not work on rootless Docker or some locked-down
  Docker Desktop / CI configurations — there's no fallback for that here)
- **4 vCPU / 16GB RAM / 30GB free disk**, matching minnaker's own stated
  minimums — this is a real Spinnaker install, just containerized; the
  footprint wasn't shrunk to fit smaller hardware. Check before running:
  this repo's own dev machine had only ~11GB free disk at the time this was
  built, which is *not* enough — confirmed the constraint rather than
  glossing over it.

## What's pinned (and why it's not a moving target)

| Component | Pinned to | Why this one |
| --- | --- | --- |
| `spinnaker-kustomize-patches` (manifests) | commit `50a095cd9aa1a83723f4cc09d6e5a78c6d96d17e` on branch `minnaker` | `armory/minnaker`'s own release tags (latest: `v0.1.3`, 2021-04-30) don't correspond to fixed manifest content — the manifests its installer actually applies live in this separate repo. **Correction**: an earlier version of this doc claimed this repo was "actively maintained, pushed 2025-03-07" — that was the repo's overall `pushed_at`, reflecting activity on its default branch. The `minnaker` branch itself, which is what's actually pinned here, has not been updated since **2021-03-26** — same era as `armory/minnaker`. Checked directly via `git log` on the branch, not assumed. |
| Spinnaker Operator | `armory-io/spinnaker-operator` `v1.8.11` (2025-12-04) | **Not** `armory/spinnaker-operator` (the OSS-flavor operator) — that one registers `spinnaker.io` CRDs, but this recipe's `SpinnakerService` uses `apiVersion: spinnaker.armory.io/v1alpha2`. Confirmed by downloading both operators' release manifests and checking their CRDs' `group:` field directly, not assumed from either project's docs |
| `kubectl` (in the bootstrap/port-forward image) | `v1.32.7` | Matches what was used to test-build the manifests locally (`kubectl kustomize`) before wiring this up |

If you're revisiting this later: bump the pins in
`others/minnaker/manifests/kustomization.yml` (the `?ref=` query strings)
and `others/minnaker/bootstrap/entrypoint.sh` (`KUSTOMIZE_REF`,
`OPERATOR_VERSION`) together — they're not independently versioned.

## What this adds on top of minnaker's own recipe

minnaker's default recipe (`spinnaker-kustomize-patches`'s
`kustomization-minnaker.yml`) does **not** enable Kayenta or deploy
Prometheus — those resources exist in that repo but are left commented out,
marked with a `# TODO - investigate what changes... need to support
canarying`. `others/minnaker/manifests/kustomization.yml` adds them back in
itself, using that same repo's otherwise-unused
`infrastructure/prometheus-grafana/` (an in-cluster Prometheus+Grafana).

Kayenta actually needs **two** canary service integrations, both in
`patch-canary-storage.yml`:

- **`prometheus` / `METRICS_STORE`** — based on upstream's own
  `accounts/canary/prometheus.yml`, with `baseUrl` corrected to the
  in-cluster Prometheus Service instead of upstream's placeholder
- **`aws` / `CONFIGURATION_STORE` + `OBJECT_STORE`** — Kayenta needs
  somewhere to persist canary configs and analysis results, and
  Prometheus can't serve that role (metrics-only). Upstream's recipe has
  **no example of this at all** in its `accounts/canary/` folder (checked
  both the pinned commit and current `master` — only Datadog, Dynatrace,
  Stackdriver, Prometheus). Modeled on
  [Armory's documented shape](https://github.com/armory/documentation/blob/master/_spinnaker/configure_kayenta.md)
  for an S3-compatible store via Minio, pointed at the same in-cluster
  Minio `persistentStorage` already uses. This was the actual root cause
  of the `SpinnakerService validation failed: there is no account of type
  CONFIGURATION_STORE and OBJECT_STORE configured` error — not a
  version-compatibility issue as first suspected, just a genuinely missing
  piece of config upstream never documented for this case.

Both integrations live in one file, not two, because `config` is
`x-kubernetes-preserve-unknown-fields: true` in the CRD schema (confirmed
directly, not assumed) — nested arrays like `serviceIntegrations` get
replaced wholesale on patch, not merged, so two separate patch files
targeting the same array would clobber each other.

A second local patch, `patch-local-access.yml`, overrides the recipe's
hardcoded `https://spinnaker.mycompany.com` URLs to match this setup's
`localhost:8084`/`localhost:9000` port-forwards instead of the
single-hostname Traefik ingress minnaker assumes on a real VM.

## Quickstart

```bash
cd others/minnaker
docker compose up -d
```

The `bootstrap` container polls until k3s is ready, installs the Operator,
applies the manifests above, and polls the `SpinnakerService` resource
until healthy, then exits 0. `port-forward` waits for `bootstrap` to
succeed, then forwards Gate and Deck to the host:

- Deck (UI): http://localhost:9000
- Gate (API): http://localhost:8084

Watch bootstrap progress: `docker compose logs -f bootstrap`

## Access

Basic auth is enabled (upstream's recipe default). Credentials come from
`secrets-example.env`'s placeholder values, not anything secret-worthy —
this is a disposable test stack:

- Username: `username2replace`
- Password: `xxx`

Deck (browser): go to http://localhost:9000, sign in with the above —
confirmed working through an actual login flow, not just a health check.

Gate (API):

```bash
curl -u username2replace:xxx http://localhost:8084/api/credentials
```

To test `spinnaker/dinghyfile`, `POST` its pipeline JSON to Gate's
pipeline API with the same credentials — no Dinghy sync is installed here
(see "What this does NOT do"), so applying pipeline definitions is manual.

## Teardown

```bash
docker compose down -v
```

Removes all containers and named volumes (`k3s-server`, `kubeconfig`) —
nothing persists outside this compose project.

## Current status (last run against a real Docker daemon)

**Confirmed fully working**, end to end, by actually watching it happen:

- `bootstrap` brings up k3s, installs the Operator, applies every
  manifest, and exits 0 — `SpinnakerService is healthy`
- `curl http://localhost:9000/` (Deck) → `200`
- `curl http://localhost:8084/api/health` (Gate) → `200`,
  `{"status":"UP"}`
- Every core Spinnaker microservice pod is `1/1 Running`: Deck, Gate,
  Orca, Clouddriver, Front50, Echo, Igor, Rosco, Dinghy, **Kayenta**
- Hit Kayenta's own health endpoint directly (`kubectl exec` into its
  pod): `"status":"UP"`, `configServer: UP` — confirming it can actually
  read from the Minio config/object store this setup wired up, not just
  that the pod is running
- Gate's API responds to authenticated calls (`curl -u
  username2replace:xxx http://localhost:8084/api/credentials` — the
  disposable placeholder password from upstream's sample secrets file,
  see `patch-canary-storage.yml`'s neighbor `spin-secrets`)

Every bug below was a real failure caught by actually running this
end-to-end — none were anticipated in advance:

| Issue | Fix |
| --- | --- |
| `kubectl apply -k` needs `git` on PATH to fetch remote bases | Added `git` to `bootstrap/Dockerfile` |
| A multi-document `$patch: delete` file crashed kustomize (kyaml v0.18.1 segfault) | Split into one resource per patch file |
| `mysql:5.7` has no ARM64 image (`ImagePullBackOff` on Apple Silicon) | Patched to `mysql:8.0.36` + `mysql_native_password` auth plugin |
| Old recipe's `Ingress` uses removed `networking.k8s.io/v1beta1` | Deleted via patch — not needed, we use port-forward |
| Grafana resources hardcoded to `namespace: monitoring` conflict with `-n spinnaker` apply | Deleted via patch — Kayenta only needs Prometheus, not the dashboards |
| `spin-sa` has no auto-created token Secret (k8s 1.24+ behavior change) | Two-pass apply + manually created token Secret in `entrypoint.sh` |
| Hardcoded `config.version: 2.21.4` — BOM no longer resolvable | Bumped to `2.34.0` |
| `SpinnakerService validation failed: no account of type CONFIGURATION_STORE and OBJECT_STORE configured` | Upstream's recipe has **no example** of this — added an `aws`/Minio canary service integration modeled on Armory's docs (see "What this adds" above). This was the actual blocker, not an Operator-version mismatch as first suspected |
| `armory/terraformer` has no ARM64 image, and blocked the aggregate `SpinnakerService` health check | Disabled Terraform integration via patch (unrelated to Kayenta/canary testing) + manually deleted the already-created Deployment (config change alone didn't prune it) |
| StatefulSet/Deployment pods don't auto-recreate on a patch alone in every case | Not automated — occasionally needed a manual `kubectl delete pod` during testing to force a stuck pod to pick up a new image/config; if `bootstrap` seems stuck, check `kubectl -n spinnaker get pods` for anything not `Running` |

**Dead end, confirmed, don't retry without new information**: tried
pinning an Operator version contemporary with this recipe (`v1.2.5`,
released 2021-03-17, 9 days before the pinned manifests commit), hoping
older, looser validation would sidestep the storage-account issue before
its actual cause was found. Doesn't work at all — its webhook server
crashes on startup (`error starting webhook server: the server could not
find the requested resource`), registering against an
`admissionregistration` API version already removed from a modern (2026)
Kubernetes — same category of problem as the `Ingress` fix above, just
inside compiled operator code that can't be patched. Confirmed by
directly swapping the running Operator's image and watching it
crash-loop. Reverted to `v1.8.11`, which is what actually works.

## What this does NOT do

- **Does not sync `spinnaker/dinghyfile` automatically.** No Dinghy
  install here — apply pipeline JSON directly via the Spinnaker API
  (Gate is reachable and authenticated calls work, confirmed above).
- **Does not push to a real external registry.** The local `registry:2`
  service (see below) is throwaway/HTTP-only and only trusted by this
  compose project's own k3s node — it's a stand-in for CI's real registry,
  not a replacement for one.
- Everything above has been exercised, including `patch-local-access.yml`'s
  CORS override — confirmed with an actual browser (Playwright), not just
  `curl`: signed into Deck's login form at `localhost:9000`, landed on the
  real app (title "Infrastructure"), and watched it make a full sequence
  of authenticated calls to Gate at `localhost:8084`
  (`/api/auth/user`, `/api/login`, `/api/credentials`, `/api/plugins/deck/...`,
  `/api/notifications/metadata`, `/api/jobs/preconfigured`, `/api/securityGroups`)
  — all `200`, zero console/request errors.

## Local registry, app deployment, and Kayenta canary analysis — confirmed working end to end

As of the `integrate-local-spinnaker` change, this stack has been extended
and actually exercised well beyond the control-plane-only state above:

- **A local, disposable registry** (`registry:2`, compose service
  `registry`) that both the host and k3s trust. Host-side push uses
  `localhost:5050` (not `5000` — macOS's AirPlay Receiver squats on that
  port and silently intercepts requests even with Docker also publishing
  it, confirmed via `lsof -iTCP:5000`); in-cluster pulls use
  `registry:5000` via a `registries.yaml` mounted into the `k3s` service
  at `/etc/rancher/k3s/registries.yaml`, marking it as a trusted
  plain-HTTP mirror.
- **`apps/backend` deployed via `helm/` across all three tracks**
  (`production`, `canary`, `baseline`) into the `spinnaker` namespace,
  pulling from that local registry — confirmed via exact image-digest
  match on the running pods, not just "pod is Running".
- **Prometheus already scrapes the deployed app with zero new config** —
  the upstream recipe's `kubernetes-pods` scrape job (annotation-based
  discovery) combined with `helm/templates/deployment.yaml`'s existing
  `prometheus.io/scrape` annotations was sufficient. No new patch needed;
  confirmed via Prometheus's own `/api/v1/targets` (`health: "up"` for all
  9 app pods) and real query results for `http_requests_total` /
  `http_request_duration_seconds_bucket`, filtered by `track`.
- **Kayenta's canary judgement genuinely discriminates pass vs. fail
  against real Prometheus data**, confirmed with two real runs:
  - Healthy canary (identical image/config to baseline): **score 100,
    Pass**
  - Deliberately degraded canary (`FAULT_INJECT_5XX_RATE=0.7`,
    `FAULT_INJECT_LATENCY_MS=400` — env vars added to
    `apps/backend/server.js`, wired through `helm/`'s new `env:` values
    support): **score 50, Fail** (below the `marginal` threshold)
  - Both runs called Kayenta's own standalone `POST
    /canary/{canaryConfigId}` API directly (`metricsAccountName=prometheus`,
    `storageAccountName=configurationAccountName=minio-canary-store`) —
    see "Known limitation" below for why this bypasses the Spinnaker
    pipeline's `canaryAnalysis`/`kayentaCanary` stage specifically.
  - This required fixing two real, version-specific bugs in
    `spinnaker/canary-config.json`, only discoverable by actually running
    a judgement and reading the resulting errors: `customFilter` is
    deprecated in this Kayenta version (`customInlineTemplate` with a
    `PromQL:` prefix is required for a verbatim query — traced via
    bytecode decompilation of `PrometheusMetricsService.buildQuery`,
    since neither the error message nor any bundled docs stated the
    prefix requirement), and the 5xx-rate query needed
    `sum(...) or vector(0)` — without it, pods with zero errors during
    the analysis window have no matching Prometheus time series at all
    (not a zero value), which the judge was classifying as `NODATA`
    rather than "0 errors".

### Resolved: the Orca `kayentaCanary` pipeline stage is broken in this bundled version — worked around by redesigning the pipeline

`spinnaker/dinghyfile`'s native `canaryAnalysis`/`kayentaCanary` stage type
has a real, unresolved bug in this bundled Spinnaker version (root-cause
investigation below, never solved). Rather than leave the pipeline unable
to run end-to-end, `spinnaker/dinghyfile` now replaces that single stage
with a small sequence of stages that gets the same result by calling
Kayenta's own standalone API directly — proven to work correctly — instead
of routing through Orca's broken native integration:

- **`Compute Analysis Window`** (`evaluateVariables`) computes `startTime`/
  `endTime` at trigger time via SpEL (`T(java.time.Instant).now()...`),
  since a real trigger can happen whenever.
- **`Generate Traffic`** (`runJob`) fires 300 requests each at the
  canary/baseline services' `/api/hello` so the analysis window has real
  data — mirrors what earlier manual testing did by hand.
- **`Start Canary Judgement`** (`webhook`, `waitForCompletion: false`)
  `POST`s to Kayenta's `/canary/{canaryConfigId}` directly.
- **`Poll Canary Judgement`** (`webhook`, `waitForCompletion: true`,
  `statusUrlResolution: getMethod`) polls the same URL via `GET` until
  done.
- **`Check Canary Score`** (`checkPreconditions`, `expression` type)
  inspects the actual judge classification and fails the pipeline (via
  `failPipeline: true`) if it's `Fail`, gating `Bake Production`/`Promote
  to Production` exactly like the native stage would have.

**Two real gotchas hit implementing this, only discoverable by actually
triggering the pipeline and reading what came back:**

- The `Poll Canary Judgement` webhook's `statusJsonPath` must point at a
  field that's *always present* in the response, e.g. `$.status`
  (`"running"` → `"succeeded"`/`"terminal"`) — **not** a field like
  `$.result.judgeResult.score.classification` that's absent until the
  judgement completes. Orca's `MonitorWebhookTask` treats an unresolvable
  JsonPath as a hard `TERMINAL` failure (`"Unable to parse status: JSON
  property '...' not found in response body"`), not "keep polling and try
  again later" — confirmed via a real failed run, then via decompiling
  `MonitorWebhookTask.execute()`.
- The stage's **final, actual polled response lives at
  `context.webhook.monitor.body`**, not `context.webhook.body` (that key
  holds a stale snapshot of the very first `POST`'s response, frozen at
  `Start Canary Judgement` time, and never updates). A `Check Canary Score`
  expression pointed at `webhook.body...` fails with `EL1012E: Cannot index
  into a null value` even on a stage that polled and completed correctly —
  found by comparing the two keys' actual contents on a completed run.

**Also found along the way (a real metric-tuning issue, not a plumbing
bug):** the first few end-to-end runs got a spurious `Fail` on the `HTTP
p95 Latency` metric even for an unmodified canary, with suspiciously tiny
reported variance. Cause: `apps/backend/server.js`'s Prometheus histogram
buckets (`[0.1, 0.3, 0.5, ...]`) are too coarse for this app's actual
0–200ms latency range — everything falls in a single bucket, so
`histogram_quantile`'s interpolation loses most of its real variance and
becomes hypersensitive to run-to-run noise. Fixed with finer buckets
(`[0.02, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.5, 0.7, 1, 3, 5]`).

**Verified end-to-end, both directions**, triggering the real pipeline via
Gate (not just the standalone API):
- Healthy canary: all 11 stages `SUCCEEDED` including `Promote to
  Production`, judge score **100, Pass**.
- Degraded canary (env-var fault injection, see below): `Check Canary
  Score` correctly fails the pipeline before `Bake Production` ever runs.

One more real gotcha hit reaching the clean Pass: after fixing the
histogram buckets and rebuilding the image, two consecutive pipeline runs
still judged against the *old* image digest — `deployManifest` re-applying
an unchanged `image:tag` string doesn't make Kubernetes repull or restart
pods by default. Fixed permanently by adding `imagePullPolicy: Always` to
`helm/templates/deployment.yaml`, not just as a one-off `kubectl patch`.

#### Original bug investigation (root cause never found)

`spinnaker/dinghyfile`'s `bakeManifest` and `deployManifest` stages work
correctly when submitted to Gate as a real Spinnaker pipeline (verified:
bake renders the Helm chart from an embedded/base64 artifact, deploy
applies it via the `spinnaker` Kubernetes account). The native
`canaryAnalysis`/`kayentaCanary` stage type does not — even with the
correct type and a context shape confirmed byte-for-byte correct (verified
by decompiling `KayentaCanaryStage.beforeStages` and
`StageExecutionImpl.mapTo`, and by reading the exact persisted context
back out of Orca's own MySQL `pipeline_stages` table), the stage fails
with `Unable to map context to class ...KayentaCanaryContext` — a
`JsonPointer("/canaryConfig")` resolution that inexplicably returns a
missing node against a context that demonstrably has that key. Root cause
never found (see the investigation rounds below); routed around instead,
per the resolution above.

**Tried and ruled out**: downgrading `config.version` to `2.28.0` to check
if the bug is version-specific. Never got far enough to retest it —
`spin-clouddriver` deadlocked on `2.28.0` instead (process alive, port
7002 completely unresponsive, no log output at all for minutes; `2.34.0`'s
clouddriver recovered cleanly once reverted). Most likely cause: `2.28.0`'s
older bundled JDBC driver against this stack's ARM64-substituted
`mysql:8.0.36` (`mysql_native_password`, patched in for Apple Silicon —
see the pinned-components table above). Reverted to `2.34.0`, confirmed
healthy again. If revisiting: attaching a debugger to Orca directly is a
more promising next step than further version-hopping, since `2.28.0`
introduces its own incompatibility before the original question can even
be tested.

**Actuator-debug round (live introspection, no code changes retained)**:
temporarily patched the `SpinnakerService` CR's `profiles.orca` with
`management.endpoints.web.exposure.include: "*"` to get live Orca
introspection (note for next time: this bundled Orca serves actuator
endpoints at the *root* path, e.g. `http://spin-orca:8083/threaddump`, not
`/actuator/threaddump` — the base path is `""`, not the Spring Boot
default). With it live:
- `/beans` confirms Spring's `objectMapper` bean is not a distinct
  instance — its `@Bean(name = "objectMapper")` factory method
  (`WebConfiguration.orcaObjectMapper()`) just returns
  `OrcaObjectMapper.getInstance()` directly, and `StageExecutionImpl`'s
  `objectMapper` field is set to that same static singleton in every
  constructor (confirmed by bytecode). So "a different ObjectMapper bean
  wired in via DI" is ruled out — there is genuinely only the one
  singleton in play, live and in the standalone harness alike.
- Decompiling `MissingNode.asToken()` (jackson-databind 2.13.5) confirms
  it returns `JsonToken.NOT_AVAILABLE` — so the exact exception text
  (`Cannot deserialize ... from [Unavailable value] (token
  JsonToken.NOT_AVAILABLE)`) is Jackson's standard behavior when
  `ObjectNode.at("/canaryConfig")` resolves to a `MissingNode`, i.e. a
  plain "key not found at that pointer" — not a value/type mismatch. This
  confirms (rather than newly discovers) the "missing node" framing
  already stated above, just traced to its exact Jackson mechanism.
- DEBUG-level logging on `KayentaCanaryStage`, `StageExecutionImpl`, and
  `com.fasterxml.jackson.databind` produced no additional log lines beyond
  the existing WARN/ERROR stack traces — this code path has no
  debug-level logging to reveal, so DEBUG logging is a dead end here.
- The stage fails in under 100ms of being started (`beforeStages` runs
  synchronously before any task), too fast to catch with a polled
  `/threaddump` from outside the process.
- Checked whether Orca's SQL execution-body compression feature
  (`ExecutionCompressionProperties`, default `enabled: false`,
  1024-byte/ZLIB threshold) could explain large-execution-only corruption,
  given this pipeline's completed body is ~93KB — confirmed compression is
  not enabled in this stack's config (`orca-local.yml`/`orca.yml` have no
  `compression` keys), so ruled out.
- Net result: this round narrowed the *mechanism* (definitely a JSON
  Pointer miss, definitely the same singleton ObjectMapper) but did not
  find why `stage.context`, serialized via `valueToTree()` at the instant
  `mapTo` runs, lacks the `canaryConfig` key that the post-failure
  diagnostic dump (captured from the same object, an instant later) does
  show. Root cause still not found.
