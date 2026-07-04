## ADDED Requirements

### Requirement: Locally-built image is pullable inside the minnaker cluster
The system SHALL provide a throwaway container registry reachable both from the host Docker daemon and from the minnaker-managed k3s cluster, so an image built from `apps/backend` can be pushed from the host and pulled by pods running in that cluster.

#### Scenario: Building and pushing the app image
- **WHEN** a contributor builds `apps/backend`'s image from repo root and pushes it to the local registry
- **THEN** the push succeeds without requiring any real (non-placeholder) registry credentials

#### Scenario: k3s pulling the pushed image
- **WHEN** a Helm-deployed pod in the minnaker cluster references an image tag hosted on the local registry
- **THEN** k3s's containerd pulls it successfully without TLS-verification errors, despite the registry serving plain HTTP

### Requirement: apps/backend deployed across all three Helm tracks
The system SHALL support deploying `helm/` into the minnaker-managed cluster for each of `production`, `canary`, and `baseline` tracks simultaneously, coexisting in the same namespace per the chart's existing track-based naming/selector convention.

#### Scenario: Three tracks running concurrently
- **WHEN** a contributor runs `helm install`/`upgrade` for `production`, `canary`, and `baseline` tracks with `--set track=<track>` against the minnaker cluster
- **THEN** three independent, non-colliding sets of Deployment/Service resources are Running, each selectable by its track label

### Requirement: Prometheus scrapes real canary/baseline metrics
The in-cluster Prometheus installed by `others/minnaker/manifests` SHALL be configured to scrape `/metrics` from the deployed `apps/backend` pods across all tracks, so Kayenta's Prometheus metrics account has real time series to query.

#### Scenario: Metrics visible to Kayenta's account
- **WHEN** `apps/backend` pods have been running and receiving traffic for at least one scrape interval
- **THEN** querying Prometheus (directly, or via Kayenta's own health/config check) for `http_requests_total` and `http_request_duration_seconds_bucket` filtered by `track` returns non-empty series for each deployed track

### Requirement: Pipeline executes end-to-end against live infrastructure
`spinnaker/dinghyfile`'s pipeline SHALL be submitted to Gate and executed for real against the local stack, running its `bakeManifest`, `canaryAnalysis`, and `deployManifest` stages against the actual deployed resources and actual Prometheus data — not a dry run or a structural check.

#### Scenario: Submitting the pipeline
- **WHEN** a contributor POSTs the rendered `dinghyfile` pipeline JSON to Gate's pipeline-save endpoint, authenticated with the stack's placeholder credentials
- **THEN** Gate accepts and persists the pipeline, and it becomes triggerable via the Spinnaker API

#### Scenario: Healthy canary run promotes
- **WHEN** the pipeline is triggered with a canary/baseline image whose behavior matches production (no injected fault)
- **THEN** the `canaryAnalysis` stage's score meets or exceeds `scoreThresholds.pass` (90), and the `Promote to Production` stage executes and updates the production track's image tag

#### Scenario: Degraded canary run is blocked
- **WHEN** the pipeline is triggered with a canary image carrying an injected fault that elevates its `5xx` rate or `p95` latency relative to baseline
- **THEN** the `canaryAnalysis` stage's score falls below `scoreThresholds.marginal` (75), and the `Promote to Production` stage does not execute
