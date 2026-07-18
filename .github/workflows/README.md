# Workflows

| File | Trigger | What it does |
| --- | --- | --- |
| `pages.yml` | push to `main` touching `site/**` | Deploys the architecture doc to GitHub Pages |
| `build-and-push.yml` | push to `main` touching app code | Builds and pushes an image to `ghcr.io` — feeds `spinnaker/dinghyfile`'s Docker trigger, which handles canary analysis and promotion. Does not deploy anything itself. |
| `pr-preview.yml` | PR opened/synchronized/reopened (same-repo only, not forks) | Builds an image, then deploys an approval-gated, isolated preview environment (`pr-<number>`) |
| `pr-cleanup.yml` | PR closed | Tears down that PR's preview environment |

## One-time repo setup for `pr-preview.yml`

**1. Create the `pr-preview` Environment** (Settings → Environments → New environment, name it `pr-preview`):
- Add required reviewers under "Deployment protection rules" — this is what makes the `deploy` job in `pr-preview.yml` pause for approval before touching the cluster. Without this, the environment gate is a no-op.

**2. Add the `KUBE_CONFIG` secret** (Settings → Secrets and variables → Actions → New repository secret), once a real, GitHub-Actions-reachable Kubernetes cluster exists:
- Value: a kubeconfig file, **base64-encoded** (`cat your-kubeconfig.yaml | base64 | pbcopy` on macOS, then paste)
- Scope: ideally a service account limited to the namespace(s) these workflows deploy into, not full cluster-admin
- Until this secret is set, `pr-preview.yml`'s `deploy` job and `pr-cleanup.yml`'s `cleanup` job fail/skip loudly and explicitly rather than with a confusing connection error — this is expected and by design, not a bug (see `openspec/changes/add-pr-preview-pipeline/design.md`'s Non-Goals). `others/minnaker` (this repo's local docker-compose Spinnaker instance) is not reachable from GitHub's hosted runners and cannot serve as this cluster as-is.
