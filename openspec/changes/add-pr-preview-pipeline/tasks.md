## 1. Resolve the registry placeholder

- [x] 1.1 Update `helm/values.yaml`'s `image.repository` from placeholder to `ghcr.io/pohsiu/my-spinnaker-canary-app`
- [x] 1.2 Update `spinnaker/dinghyfile`'s `triggers[].repository` to match — also updated `registry` (was `index.docker.io`) and all 3 `image.repository` override occurrences in the pipeline stages for consistency; confirmed still valid JSON
- [x] 1.3 Confirmed: `helm lint` passes (0 failed), `helm template` renders `image: "ghcr.io/pohsiu/my-spinnaker-canary-app:abc123"` correctly

## 2. `build-and-push.yml` (main → image)

- [x] 2.1 Created `.github/workflows/build-and-push.yml`, triggered on `push` to `main` (path-filtered to app/package files, avoids rebuilding on doc-only changes)
- [x] 2.2 Builds from `apps/backend/Dockerfile` with context `.` (repo root, matching the existing README's documented `docker build` command)
- [x] 2.3 Authenticates via `docker/login-action` with `secrets.GITHUB_TOKEN`, `permissions: packages: write` on the job — no new secret
- [x] 2.4 Pushes `ghcr.io/<owner>/my-spinnaker-canary-app:<sha>`; no deploy step exists in this workflow. Validated with `actionlint` (authoritative GitHub Actions linter, installed via brew) — zero issues.

## 3. `pr-preview.yml` (PR → approval-gated deploy)

- [x] 3.1 Created `.github/workflows/pr-preview.yml`, triggered on `pull_request: [opened, synchronize, reopened]`
- [x] 3.2 Fork guard on the `build` job: `if: github.event.pull_request.head.repo.full_name == github.repository`; `deploy` depends on `build` so it's transitively skipped too for fork PRs
- [x] 3.3 Builds and pushes `pr-<number>-<short-sha>` (short SHA computed from `github.event.pull_request.head.sha`, not the merge-commit SHA `pull_request` checks out by default, so the tag reflects the actual PR commit)
- [x] 3.4 `deploy` job depends on `build`, `environment: pr-preview` — approval gate
- [x] 3.5 `helm upgrade --install pr-<number> helm/ --set track=canary --set image.tag=<tag>` against a kubeconfig decoded from `KUBE_CONFIG`
- [x] 3.6 Added an explicit `KUBE_CONFIG` presence check as its own step, `exit 1` with a clear `::error::` message before attempting any kubectl/helm calls
- [x] 3.7 Added a PR-comment step via `actions/github-script` with `kubectl port-forward svc/pr-<number>-canary 3000:3000` — verified the service name matches the chart's actual `{{ .Release.Name }}-{{ .Values.track }}` naming and `service.port: 3000` in `values.yaml`, not just assumed. `actionlint` (authoritative GH Actions linter) passes clean.

## 4. `pr-cleanup.yml` (PR closed → teardown)

- [x] 4.1 Created `.github/workflows/pr-cleanup.yml`, triggered on `pull_request: [closed]` — no `if: merged` check, cleans up either way
- [x] 4.2 Runs `helm uninstall pr-<number>` against `KUBE_CONFIG`; skips (with a `::warning::`, not a failure) if the secret isn't set, same reasoning as `pr-preview.yml`
- [x] 4.3 `helm uninstall ... || echo "..."` — tolerates "release not found" since the deploy job requires manual approval and may never have run for a given PR. `actionlint` passes clean.

## 5. Repo configuration (outside tracked files)

- [x] 5.1 Created `.github/workflows/README.md`: a workflow table plus "one-time repo setup" steps for creating the `pr-preview` Environment and adding required reviewers
- [x] 5.2 Documented `KUBE_CONFIG` contents (base64-encoded kubeconfig), recommended scoping (namespace-limited service account, not cluster-admin), and explicitly noted `others/minnaker` cannot serve as this cluster as-is (local-only, unreachable from hosted runners)

## 6. Verification

- [ ] 6.1 Open a throwaway PR from a same-repo branch; confirm the build runs and the deploy job pauses for approval
- [ ] 6.2 Confirm a fork PR (or a simulated `workflow_dispatch` with a mismatched `head.repo.full_name`) does not trigger build/deploy
- [ ] 6.3 Close the throwaway PR without merging; confirm `pr-cleanup.yml` runs (deploy step will fail loudly on missing `KUBE_CONFIG` until a real cluster exists — expected per design.md, not a bug to chase)
- [ ] 6.4 Push a commit to `main`; confirm `build-and-push.yml` runs and pushes an image to `ghcr.io`
- [ ] 6.5 Note in this change's final summary exactly what was verified for real (workflow YAML validity, trigger conditions) vs. what remains unverified pending a real cluster (actual `helm upgrade`/`uninstall` success) — do not overclaim
