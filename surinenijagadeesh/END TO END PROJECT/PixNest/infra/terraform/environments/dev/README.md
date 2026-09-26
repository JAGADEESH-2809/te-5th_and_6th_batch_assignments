# Environment: dev

The live `dev` environment (ap-south-1). It composes the shared
[`../../modules`](../../modules) and keeps its own state at `env/dev/terraform.tfstate`.

Nothing account-specific is committed here: the account id arrives via the assumed role, and
the state bucket via `-backend-config` (see [Run](#run)). The same code applies to any account.

## What it deploys
- `module.vpc` - VPC, public/private subnets across 2 AZs, NAT, flow logs, S3 gateway endpoint
- `module.eks` - the EKS cluster, managed node group and add-ons (incl. EBS CSI)
- `module.ecr` - the two image registries
- `module.s3` - the photos bucket (`force_destroy = true` here, so demo teardowns are clean)
- `module.github_oidc` - the CI push role
- `module.pod_identity` - backend Pod Identity (only when `enable_pod_identity = true`)

## Run
Normally via the `terraform` pipeline (plan on PR, apply on main), keyless through the
`pixnest-tf` role. The pipeline supplies the backend bucket from the `TF_STATE_BUCKET` repo
variable, which [`bootstrap-aws.sh`](../../../scripts/bootstrap-aws.sh) sets.

Locally, pass the same partial-backend values the pipeline does:
```bash
terraform init -reconfigure \
  -backend-config="bucket=pixnest-tfstate-$(aws sts get-caller-identity --query Account --output text)" \
  -backend-config="region=ap-south-1"
terraform plan
```
Or, to check syntax with no AWS access at all:
```bash
terraform init -backend=false && terraform validate
```

## Add another environment (staging/prod)
Copy this directory, then in the copy: change `backend.tf`'s `key` and the values in
`terraform.tfvars` (including `environment`, which drives the Environment tag). Each environment has fully isolated state.

## Variables / Outputs
No variable has a default: every value is set in `terraform.tfvars`, so that one file is the
complete, reviewable description of the environment. See `variables.tf` and `outputs.tf`. Key outputs: `ecr_backend_url`, `ecr_frontend_url`,
`s3_bucket`, `github_actions_role_arn`, `backend_role_arn`.


