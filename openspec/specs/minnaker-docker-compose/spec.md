# minnaker-docker-compose Specification

## Purpose

TBD — created by archiving change `minnaker-docker-compose`. Update this Purpose statement to describe the capability's role in the system.

## Requirements

### Requirement: Compose-managed Spinnaker instance
The system SHALL provide a `docker-compose.yml` under `others/minnaker/` that brings up a k3s-in-Docker Kubernetes cluster and, on top of it, a Spinnaker Operator–managed `SpinnakerService` reproducing minnaker's default stack (Minio, MySQL, Redis, Spinnaker Operator, Kayenta enabled).

#### Scenario: Bringing up the stack from a clean checkout
- **WHEN** a contributor with Docker (privileged-container support) runs `docker compose -f others/minnaker/docker-compose.yml up -d` on a host meeting the documented resource minimums
- **THEN** the k3s server container reaches Ready, the bootstrap container applies all manifests in order and exits 0, and the Spinnaker Operator reports the `SpinnakerService` resource as healthy

#### Scenario: Bootstrap ordering is enforced
- **WHEN** the bootstrap container starts before the k3s API server is accepting connections
- **THEN** the bootstrap container polls `kubectl get nodes` and retries rather than failing on the first attempt

### Requirement: Host-reachable Spinnaker UI and API
The system SHALL expose Spinnaker's Gate (API) and Deck (UI) on host-mapped ports without requiring the contributor to configure k3s ingress or obtain a cluster-internal IP manually.

#### Scenario: Reaching Deck after bootstrap completes
- **WHEN** the bootstrap container has exited 0 and the port-forward sidecar container is running
- **THEN** `http://localhost:9000` (Deck) and `http://localhost:8084` (Gate) respond from the host machine

### Requirement: Full teardown with no residual state
The system SHALL leave no persistent state outside the compose project's own named volumes, so a full teardown returns the host to its pre-`up` state.

#### Scenario: Tearing down the stack
- **WHEN** a contributor runs `docker compose -f others/minnaker/docker-compose.yml down -v`
- **THEN** all containers, networks, and named volumes created by this compose project are removed, and no k3s state persists on the host filesystem outside those volumes

### Requirement: Manifests pinned to a specific upstream commit
The system SHALL fetch minnaker's actual recipe manifests from a specific, named commit SHA of `armory/spinnaker-kustomize-patches`'s `minnaker` branch (recorded in `others/minnaker/README.md` and in `others/minnaker/manifests/kustomization.yml`'s `ref=`), not from that repo's default branch or a `armory/minnaker` release tag — the `minnaker` repo itself does not vendor the manifests its installer applies.

#### Scenario: Reproducing the exact stack later
- **WHEN** a contributor reads `others/minnaker/README.md` months after this change merges
- **THEN** the pinned `spinnaker-kustomize-patches` commit SHA is stated explicitly, so the contributor can compare against or re-fetch the exact manifests `kubectl apply -k` used at that commit

### Requirement: Kayenta and a metrics account enabled by default
The `SpinnakerService` manifest SHALL enable Kayenta and configure a Prometheus-backed metrics account by default, so this repo's `spinnaker/canary-config.json` has a metrics account to reference once a Prometheus instance is wired up.

#### Scenario: Kayenta stage available after bring-up
- **WHEN** the stack finishes bootstrapping
- **THEN** Spinnaker's config reports Kayenta as an enabled feature and at least one Prometheus metrics account is registered (even if it has no scrape targets yet)

### Requirement: Documented scope boundary
`others/minnaker/README.md` SHALL state explicitly what this stack does and does not provide, specifically: it stands up the Spinnaker/Kayenta control plane only, and does NOT deploy this repo's `apps/backend` into the resulting cluster or wire Prometheus to `apps/backend`'s `/metrics`.

#### Scenario: Contributor checks feasibility before running an end-to-end canary test
- **WHEN** a contributor reads the README to decide whether this stack alone is enough to test `spinnaker/dinghyfile` end-to-end against a live app
- **THEN** the README states that a registry-reachable image and a Prometheus scrape target for `apps/backend` are still required and out of scope for this stack
