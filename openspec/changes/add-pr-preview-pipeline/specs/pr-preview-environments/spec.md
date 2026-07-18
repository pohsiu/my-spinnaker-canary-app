## ADDED Requirements

### Requirement: PR environments deploy on open/update
The system SHALL build an image and deploy a PR-scoped Kubernetes environment whenever a pull request from a same-repository branch is opened, synchronized, or reopened.

#### Scenario: Opening a PR triggers a build
- **WHEN** a pull request is opened from a branch in this repository (not a fork)
- **THEN** a workflow run starts that builds a container image tagged `pr-<number>-<short-sha>`

#### Scenario: Pushing new commits to an open PR redeploys it
- **WHEN** a new commit is pushed to an already-open PR's branch
- **THEN** the workflow re-runs, builds a new image tag reflecting the new commit, and updates that PR's deployed environment to it

### Requirement: Fork PRs do not trigger preview deployment
The system SHALL NOT build or deploy a preview environment for pull requests originating from a forked repository.

#### Scenario: Fork PR opened
- **WHEN** a pull request is opened whose head repository is not this repository
- **THEN** no build or deploy job runs for it

### Requirement: Preview deploys require approval
The system SHALL require an approval on a designated GitHub Environment before deploying a PR's built image to the cluster.

#### Scenario: Build completes, deploy waits for approval
- **WHEN** a same-repo PR's image build succeeds
- **THEN** the workflow pauses at the deploy job, targeting the `pr-preview` Environment, until a required reviewer approves it

#### Scenario: Approval granted
- **WHEN** a required reviewer approves the pending deployment
- **THEN** the workflow proceeds to deploy that PR's environment

### Requirement: Each PR gets an isolated, uniquely-named deployment
The system SHALL deploy each PR's environment as a distinct Helm release named `pr-<number>`, without requiring changes to the Helm chart's existing templates.

#### Scenario: Two PRs open simultaneously
- **WHEN** PR #123 and PR #124 both have approved, deployed preview environments at the same time
- **THEN** their Kubernetes resources are named distinctly (e.g. `pr-123-canary` and `pr-124-canary`, per the chart's existing `{{ .Release.Name }}-{{ .Values.track }}` naming) and neither overwrites or conflicts with the other

### Requirement: PR environments are torn down on close
The system SHALL remove a PR's deployed environment when that PR is closed, whether merged or closed without merging.

#### Scenario: PR merged
- **WHEN** a pull request with a deployed preview environment is merged
- **THEN** a workflow run removes that PR's Helm release (`helm uninstall pr-<number>`)

#### Scenario: PR closed without merging
- **WHEN** a pull request with a deployed preview environment is closed without being merged
- **THEN** the same cleanup runs and removes that PR's Helm release

### Requirement: Reviewers get access instructions
The system SHALL post instructions for reaching the deployed PR environment as a comment on the pull request, since no browser-reachable ingress exists for preview environments.

#### Scenario: Deploy succeeds
- **WHEN** a PR's preview environment finishes deploying successfully
- **THEN** a comment is posted on that PR with `kubectl port-forward` (or equivalent) instructions scoped to that PR's release name
