## ADDED Requirements

### Requirement: Pushes to main build and publish an image
The system SHALL build and push a container image to GitHub Container Registry whenever a commit is pushed to `main`.

#### Scenario: Commit pushed to main
- **WHEN** a commit is pushed directly or merged to `main`
- **THEN** a workflow run builds the image from `apps/backend/Dockerfile` and pushes it to `ghcr.io/pohsiu/my-spinnaker-canary-app`, tagged with the commit SHA

### Requirement: This workflow does not deploy
The system SHALL NOT perform any deployment, canary analysis, or promotion as part of the `main` build-and-push workflow — that remains the responsibility of `spinnaker/dinghyfile`'s existing Docker trigger.

#### Scenario: Image push completes
- **WHEN** the built image finishes pushing to the registry
- **THEN** the workflow run ends there; no Helm/kubectl deploy step runs as part of it

### Requirement: No new secrets required for registry push
The system SHALL authenticate to the container registry using the workflow's built-in `GITHUB_TOKEN`, without requiring a new repository secret to be provisioned.

#### Scenario: Workflow runs on a repo with no additional secrets configured
- **WHEN** this workflow runs on a fresh checkout of this repo with no registry credentials added beyond what GitHub provides automatically
- **THEN** the image push to `ghcr.io` succeeds
