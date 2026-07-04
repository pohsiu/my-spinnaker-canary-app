## MODIFIED Requirements

### Requirement: Documented scope boundary
`others/minnaker/README.md` SHALL state explicitly what this stack does and does not provide. As of this change, the stack additionally provides a local registry reachable from the cluster and a Prometheus scrape target wired to a real deployed app — it is no longer "control plane only." The boundary statement SHALL be updated to reflect that `apps/backend` deployment, image delivery, and metrics scraping are now exercised, while stating what remains genuinely out of scope: Dinghy git-sync (pipelines are still applied manually via Gate), and any real (non-local) container registry or CI trigger.

#### Scenario: Contributor checks feasibility before running an end-to-end canary test
- **WHEN** a contributor reads the README to decide whether this stack alone is enough to test `spinnaker/dinghyfile` end-to-end against a live app
- **THEN** the README confirms this has been done (local registry + Prometheus scrape + Helm deploy + pipeline execution, both pass and fail canary cases), and states that only Dinghy git-sync and a real external registry remain unimplemented
