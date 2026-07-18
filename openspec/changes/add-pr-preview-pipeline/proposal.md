## Why

There's currently no CI pipeline in this repo beyond GitHub Pages (`.github/workflows/pages.yml`). Two gaps this addresses: (1) `spinnaker/dinghyfile`'s Docker trigger has never had anything actually building and pushing images for it to react to, and (2) there's no way to see a PR's changes running as a live environment before merging — reviewers only have the diff to go on.

## What Changes

- Add `.github/workflows/pr-preview.yml`: on PR open/update (same-repo branches only, not forks), builds an image, gates on a `pr-preview` GitHub Environment (required-reviewer approval), then `helm upgrade --install`s a PR-scoped release (`pr-<number>`) — reuses the existing Helm chart's `{{ .Release.Name }}-{{ .Values.track }}` naming as-is, no chart changes needed.
- Add `.github/workflows/pr-cleanup.yml`: on PR close (merged or not), `helm uninstall`s that PR's release.
- Add `.github/workflows/build-and-push.yml`: on push to `main`, builds and pushes an image tagged with the commit SHA. Stops there — deployment/canary analysis remains `spinnaker/dinghyfile`'s job, unchanged. This workflow only fills the gap of nothing ever having fed its Docker trigger.
- Resolve two of the repo's long-standing placeholders to a real value: `helm/values.yaml`'s `image.repository` and `spinnaker/dinghyfile`'s `triggers[].repository`, both set to `ghcr.io/pohsiu/my-spinnaker-canary-app` — GitHub Container Registry needs no new secret (pushes with the workflow's built-in `GITHUB_TOKEN`), unlike the cluster credentials below.
- **Not resolved, stays a placeholder**: the target Kubernetes cluster's credentials (`KUBE_CONFIG` or equivalent secret) for both `pr-preview.yml` and `pr-cleanup.yml`. No real cluster reachable from GitHub's hosted runners exists yet for this repo (`others/minnaker` is local-only, docker-compose). These workflows are structurally complete and correct but won't actually deploy anywhere until that secret is provided against a real cluster.

## Capabilities

### New Capabilities
- `pr-preview-environments`: ephemeral, approval-gated, per-PR Kubernetes deployments that automatically create on PR open/update and tear down on PR close.
- `master-image-publish`: build-and-push CI for `main`, feeding the existing (previously never-fed) Spinnaker Docker trigger.

### Modified Capabilities
(none — no existing specs cover CI/CD; this is net-new)

## Impact

- **New workflows**: `.github/workflows/pr-preview.yml`, `pr-cleanup.yml`, `build-and-push.yml`. `.github/workflows/pages.yml` is untouched.
- **`helm/values.yaml`**: `image.repository` placeholder resolved to a real value (ghcr.io). No schema/template changes — PR-scoping uses Helm release name, not a new `track` value.
- **`spinnaker/dinghyfile`**: `triggers[].repository` placeholder resolved to match. No stage changes — canary/promote logic is unaffected.
- **New GitHub repo configuration required** (outside this repo's files): a `pr-preview` Environment with required reviewers, and — once a real cluster exists — a `KUBE_CONFIG` secret scoped to it.
- **Explicitly out of scope**: provisioning an actual reachable Kubernetes cluster; per-PR ingress/routing so a reviewer can browse the deployed environment (deferred — reviewers use `kubectl port-forward` or similar in the interim, noted in design.md); fork-PR preview deployments (deliberately excluded — `pull_request` from forks doesn't get repo secrets, and using `pull_request_target` to work around that is a known GitHub Actions security footgun this repo isn't taking on).
