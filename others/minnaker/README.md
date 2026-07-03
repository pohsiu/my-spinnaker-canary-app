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

- **Does not deploy `apps/backend` into this cluster**, and does not wire
  Prometheus to `apps/backend`'s `/metrics`. This stack stands up a fully
  healthy Spinnaker/Kayenta control plane — actually running
  `spinnaker/dinghyfile` end-to-end against this repo's real app still
  needs a container registry this k3s can pull `apps/backend`'s image
  from, and a Prometheus scrape target pointed at real canary/baseline
  pods.
- **Does not sync `spinnaker/dinghyfile` automatically.** No Dinghy
  install here — apply pipeline JSON directly via the Spinnaker API
  (Gate is reachable and authenticated calls work, confirmed above).
- Everything above has been exercised, including `patch-local-access.yml`'s
  CORS override — confirmed with an actual browser (Playwright), not just
  `curl`: signed into Deck's login form at `localhost:9000`, landed on the
  real app (title "Infrastructure"), and watched it make a full sequence
  of authenticated calls to Gate at `localhost:8084`
  (`/api/auth/user`, `/api/login`, `/api/credentials`, `/api/plugins/deck/...`,
  `/api/notifications/metadata`, `/api/jobs/preconfigured`, `/api/securityGroups`)
  — all `200`, zero console/request errors.
