# GitHub Actions workflows

Two pipelines, both keyless to AWS via GitHub OIDC (no stored secrets, just role ARNs in repo
variables: `AWS_ACCOUNT_ID`, `AWS_REGION`, `AWS_TF_ROLE_ARN`, `AWS_GHA_ROLE_ARN`).

## `ci.yml` - application CI/CD
Triggers on changes to `backend/`, `frontend/`, or `infra/helm/`.
- `backend-test` - ruff lint + format check + pytest (S3/DB mocked; no cloud needed).
- `frontend-build` - npm ci + build.
- `lint-infra` - helm lint/template + terraform fmt/validate.
- `images` - on push to main, builds + pushes both images to ECR (assumes `pixnest-gha` via OIDC).
  Skipped until the AWS repo variables exist, so CI stays green before AWS is wired.
- `gitops-bump` - writes the new image tags into the backend and frontend charts' `values.yaml` and commits
  (with `[skip ci]`). Argo CD then deploys.

## `terraform.yml` - infrastructure pipeline
Multi-environment (`dev`, `prod`), keyless via OIDC, state in the S3 backend.

| Trigger | Plans | Applies |
|---------|-------|---------|
| pull request (`infra/terraform/**`, excluding `.md`) | **both** dev and prod | nothing |
| push to main (same paths) | dev | dev |
| Run workflow (dispatch) | the chosen environment | only if the action is `apply` or `destroy` |

Three jobs: `setup` decides what the run should do, `plan` produces the plan, `apply` consumes it.

- **The plan is an artifact.** `plan` uploads `tfplan` (the binary plan) plus `plan.txt`, and
  `apply` downloads that exact artifact and applies it. Nothing is re-planned at apply time, so
  what runs is byte-for-byte what was reviewed. Retention is 7 days; a plan can contain resource
  attribute values, and artifacts are readable by anyone who can read the repo.
- **The plan is also rendered twice for humans**: on the run summary page, and as a PR comment
  (one per environment, updated in place rather than appended, so the PR does not fill up with
  stale plans).
- **Expensive and irreversible actions need a typed confirmation.** Any `destroy`, and any
  `apply` to prod, requires the environment name typed into the `confirm` input; otherwise the run
  stops in the `setup` job before anything else starts. The dropdown puts `destroy` one careless
  click away from `plan`.
- **The better gate is not available on this plan.** The apply job references a GitHub Environment
  named after the target (`dev` / `prod`, both created), which is how you would add *required
  reviewers* so a second person clicks approve. Protection rules on a **private** repo need GitHub
  Pro or Team, and this repo is on Free - the API rejects the rule with "Please ensure the billing
  plan supports the required reviewers protection rule." The day the plan changes, add reviewers
  under **Settings -> Environments -> prod** and it gates every prod apply and destroy with no
  change to the workflow. The environments are also where per-environment variables and secrets
  would live.
- **Per-environment AWS config.** The role ARN, state bucket and region come from repo variables,
  preferring `<NAME>_DEV` / `<NAME>_PROD` and falling back to the shared `<NAME>`. Today both
  environments share one account, so only the shared variables are set; the day prod moves to its
  own account, add `AWS_TF_ROLE_ARN_PROD` and `TF_STATE_BUCKET_PROD` and nothing else changes.
- **Concurrency** is per environment, and never cancels a run mid-apply.

## Gotcha
Never put the literal `[skip ci]` in a commit MESSAGE unless you mean it - GitHub reads it and
skips the run (it is fine inside file contents). Use it deliberately for docs-only commits.

