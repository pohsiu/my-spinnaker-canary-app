## Context

This repo has one existing workflow (`pages.yml`) and one existing deploy pipeline (`spinnaker/dinghyfile`, triggered by a Docker registry push that has never actually happened — nothing has ever built and pushed an image for it to react to). This change adds three GitHub Actions workflows that (a) finally feed that trigger on `main`, and (b) give reviewers a live, ephemeral environment per PR instead of just a diff.

Explored in `/opsx:explore` before this proposal: the target cluster for PR previews doesn't exist yet (`others/minnaker` is local-only, unreachable from GitHub's hosted runners), so this design produces structurally-complete workflows gated on a placeholder cluster credential — the same posture this repo already takes with `helm/values.yaml`'s `image.repository` and `spinnaker/canary-config.json`'s `metricsAccountName` before this change.

## Goals / Non-Goals

**Goals:**
- PR open/update → build → approval-gated deploy of a PR-scoped environment, using the existing Helm chart unmodified
- PR close (merged or not) → tear down that PR's environment
- `main` push → build + push an image, tagged and repository-named so `spinnaker/dinghyfile`'s existing Docker trigger can pick it up — canary analysis and promotion logic stay Spinnaker's job, untouched
- Resolve the `image.repository` / `triggers[].repository` placeholders to `ghcr.io/pohsiu/my-spinnaker-canary-app` (no new secret needed — GHCR pushes with the workflow's built-in `GITHUB_TOKEN`)

**Non-Goals:**
- Provisioning a real, GitHub-Actions-reachable Kubernetes cluster — out of scope; `KUBE_CONFIG` stays a placeholder secret until one exists
- Per-PR ingress/routing/subdomains so a reviewer can browse the environment in a browser — deferred; the workflow instead comments on the PR with `kubectl port-forward` instructions (cheap, no new infra)
- Fork-PR preview deployments — deliberately excluded (see Decisions)
- Changing anything about `spinnaker/dinghyfile`'s canary/promote stages
- Resource quotas / concurrency limits across simultaneous PR environments — flagged as a risk, not solved here

## Decisions

**PR-scoping via Helm release name (`pr-<number>`), not a new `track` value.**
The chart's resource naming template is already `{{ .Release.Name }}-{{ .Values.track }}`. Deploying with `helm upgrade --install pr-123 helm/ --set track=canary` produces `pr-123-canary` — automatically unique per PR, zero chart changes. Considered adding a fourth `track` enum value (e.g. `preview`); rejected as unnecessary — `track` is semantically about *what Kayenta compares against*, not *whose environment this is*, and this change doesn't touch Kayenta at all for PR previews.

**Image tags: `pr-<number>-<short-sha>` for previews, `<sha>` for `main`. Immutable, never reused.**
Avoids any ambiguity about which build is running and sidesteps registry/kubelet image-cache staleness issues that come with mutable tags (`:latest`, `:pr-123`).

**Approval via a GitHub Environment (`pr-preview`) with required reviewers, not custom ChatOps.**
Considered a PR-comment-triggered flow (e.g. commenting `/deploy`); rejected — GitHub's built-in Environment protection rules do exactly this (pause the job, notify reviewers, resume on approval) with no custom logic to write or maintain.

**Fork PRs are excluded via `if: github.event.pull_request.head.repo.full_name == github.repository`, not `pull_request_target`.**
`pull_request` from a fork doesn't carry repo secrets by default — that's a deliberate GitHub safeguard. `pull_request_target` would restore secret access but runs with the base repo's permissions against the PR's (untrusted, unreviewed) code — a well-documented GitHub Actions security footgun. This repo doesn't need external contributors to get automatic preview deploys badly enough to take on that risk; excluded outright rather than mitigated.

**Registry: GitHub Container Registry (`ghcr.io`), not Docker Hub.**
No new secret — `GITHUB_TOKEN` (already available to every workflow run) has push access to GHCR for the repo it runs in. Docker Hub would need a new account, a new secret, and runs into free-tier pull-rate limits this repo has no reason to accept.

**Cleanup triggers on `pull_request: types: [closed]` regardless of merged status.**
A closed-without-merge PR's preview environment is just as stale as a merged one's — `github.event.pull_request.merged` isn't checked; both cases run the same `helm uninstall`.

## Risks / Trade-offs

- **[Risk] No resource quota/concurrency limit across simultaneous PR environments** — several open PRs could exhaust a small demo cluster. → Mitigation: none built into this change; flagged as a real limitation for whoever provisions the actual cluster to address (e.g. a `ResourceQuota` per namespace, or a max-concurrent-preview cap in the workflow). Not solved here since it's meaningless to size against a cluster that doesn't exist yet.
- **[Risk] `pr-cleanup.yml` failing silently leaves an orphaned environment** (e.g. `helm uninstall` errors, or the workflow itself never runs because of a GitHub outage). → Mitigation: none automated; a periodic "list releases named `pr-*` with no matching open PR" reconciliation job would catch this, but is future work, not part of this change.
- **[Risk] Self-approval on the `pr-preview` Environment** — if the PR author also has permission to approve their own environment deployment, the approval gate is not a real second-check. → Mitigation: this is a GitHub repo-settings concern (who's a valid required reviewer), not something a workflow file can enforce; documented, not solved in YAML.
- **[Trade-off] No browser-reachable preview URL** — reviewers get `kubectl port-forward` instructions via a PR comment instead of a clickable link. Acceptable for now given there's no ingress/DNS story yet; revisit once/if a real cluster with ingress exists.
- **[Trade-off] These workflows will fail at the deploy step until `KUBE_CONFIG` is a real secret** — by design, matching the rest of this repo's placeholder posture, but worth being loud about in the workflow's failure output rather than failing in a confusing way (e.g. a clear `if: secrets.KUBE_CONFIG == ''` early-exit with a message, not a cryptic `helm` connection-refused error).

## Migration Plan

No existing workflow or deployed system is modified — this is net-new files plus two placeholder-to-real-value edits (`image.repository`, `dinghyfile` trigger repository) that don't change either file's structure.

1. Add the three workflow files.
2. Repo settings (outside this repo's tracked files): create the `pr-preview` GitHub Environment, add required reviewers.
3. Open a throwaway PR to confirm `pr-preview.yml` builds, gates on approval, and — once `KUBE_CONFIG` exists — deploys; confirm `pr-cleanup.yml` tears down on close.
4. Merge to `main` once to confirm `build-and-push.yml` pushes an image `spinnaker/dinghyfile` can actually see.
5. No rollback concern beyond deleting the workflow files — nothing else depends on them existing.

## Open Questions

- **Namespace scoping for PR environments**: same namespace as production (simplest, matches the chart's current no-namespace-templating assumption) vs. a dedicated namespace per PR (better isolation, but the chart doesn't support this today and would need changes). Leaning toward same-namespace for now since it needs no chart changes, but this should be revisited once a real cluster's RBAC/quota strategy is decided — not resolved here.
- **PR-comment access instructions**: exact wording/format of the `kubectl port-forward` comment the workflow posts — left to implementation (task), not a design-level decision.
