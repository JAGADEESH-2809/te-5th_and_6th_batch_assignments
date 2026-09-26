# environments - one root config per environment

Each environment is a small root module that composes the shared [`../modules`](../modules) with
its own settings and its **own isolated remote state** (a distinct backend key). This is the
production pattern: identical building blocks, per-environment configuration and state.

| Environment | State key | Status |
|-------------|-----------|--------|
| [`dev/`](dev/) | `env/dev/terraform.tfstate` | demo - built and destroyed on demand through the `terraform` pipeline; cost-optimized (single NAT, small nodes, open API) |
| [`prod/`](prod/) | `env/prod/terraform.tfstate` | HA + hardened (NAT per AZ, restricted + private API, KMS-encrypted photos, deletion protection). Validated and planned, not yet applied. |

Both use the same modules; only the per-environment `terraform.tfvars` differs. Because both
currently share one AWS account, each sets a distinct `name_prefix` - IAM role, ECR repository
and S3 bucket names are account-unique, so a shared prefix would make the second `apply` fail.
See [`prod/README.md`](prod/README.md). Security and
observability (encryption at rest, control-plane + flow logs, IMDSv2, encrypted volumes,
S3 versioning/TLS-only, Pod Identity) come from the modules and apply to every environment.

## Add an environment (e.g. staging)
1. Copy `dev/` to `staging/`.
2. In `staging/backend.tf`, change `key` to `env/staging/terraform.tfstate`.
3. Set every value in `staging/terraform.tfvars` - there are no defaults to fall back on. In
   particular set `environment` (drives the Environment tag) and a unique `name_prefix`.
4. Add `staging` to the `environment` choice list in `.github/workflows/terraform.yml`, and to
   the pull-request matrix in its `setup` job.

Because each environment has separate state, changes in one never affect another.
