# pixnest infrastructure (Terraform)

Production-style layout: reusable **modules** composed by per-**environment** root configs, each
with its own remote state. Applied by the `terraform` GitHub Actions pipeline (plan on PR, apply
on main), keyless via OIDC (the `pixnest-tf` role).

```
infra/terraform/
├── modules/
│   ├── vpc/            VPC, 2-AZ public/private subnets, NAT, flow logs, S3 endpoint
│   ├── eks/            EKS cluster, managed nodes, add-ons (incl. EBS CSI)
│   ├── ecr/            one ECR repo per image (scan, immutable tags, cleanup)
│   ├── s3/             private encrypted photos bucket
│   ├── github-oidc/    CI role to push images to ECR (keyless)
│   └── pod-identity/   backend -> S3 via EKS Pod Identity (needs a cluster)
└── environments/
    ├── dev/            the demo environment: composes the modules, own state key
    └── prod/           HA/hardened: same modules, different tfvars + state key
```

Each folder has its own README. Add an environment by copying `environments/dev` and changing its
backend key and `terraform.tfvars`.

**One prefix keeps environments apart.** IAM role names are account-global, and ECR repository
and S3 bucket names are unique per account, so every named resource is built from the
`name_prefix` variable: `pixnest` in dev, `pixnest-prod` in prod. Sharing one account is
only possible because of that.

**No variable defaults.** Neither the environment roots nor the local modules declare defaults;
every value is set in the environment's `terraform.tfvars`, so that file is the complete,
reviewable description of the environment. (The registry modules keep their own internal
defaults for inputs we do not set.)

**Versions are pinned to the current releases and verified against live sources**, never from
memory: Terraform >= 1.15, AWS provider ~> 6.64, terraform-aws-modules/eks ~> 21.25,
terraform-aws-modules/vpc ~> 6.7 (as of 2026-09-10). The provider lock file is committed with
hashes for both linux (pipeline) and windows (laptop).

## Bootstrap (one-time, outside this config)
Exactly three things must exist before Terraform can run at all - it cannot create the place its
own state lives, nor the permission it needs to run. [`../scripts/bootstrap-aws.sh`](../scripts/bootstrap-aws.sh)
creates them with admin creds (idempotent, safe to re-run):
- S3 state bucket `pixnest-tfstate-<account-id>` (versioned, encrypted, private)
- GitHub OIDC provider (`token.actions.githubusercontent.com`)
- `pixnest-tf` role (assumed by the terraform pipeline via OIDC)

**Everything else - VPC, EKS, ECR, S3, app IAM - is created by `terraform apply` through the
pipeline.** Cluster software that is not infrastructure (StorageClass, metrics-server, the AWS
Load Balancer Controller, Argo CD)
are installed afterwards by [`../scripts/bootstrap-cluster.sh`](../scripts/bootstrap-cluster.sh),
deliberately *not* by Terraform: they are cluster configuration, and folding them into the infra
state would couple teardown of the cluster to teardown of the apps.

The bootstrap also sets the repo variables the pipelines read: `AWS_ACCOUNT_ID`, `AWS_REGION`,
`AWS_TF_ROLE_ARN`, `TF_STATE_BUCKET`, and `AWS_GHA_ROLE_ARN`. The state bucket is a *variable*
rather than a hardcoded value in `backend.tf`, because it is account-specific and must pre-date
Terraform; the pipeline passes it as `terraform init -backend-config="bucket=..."`. Net effect:
no account identifier is committed anywhere, so this repo applies to any AWS account unchanged.

## Wire the outputs into delivery
- `ecr_backend_url` / `ecr_frontend_url` -> Helm image repositories
- `s3_bucket` -> Helm `backend.env.S3_BUCKET`
- `s3_kms_key_arn` -> null in dev (SSE-S3); the photo encryption key in prod
- `github_actions_role_arn` -> GitHub repo variable `AWS_GHA_ROLE_ARN`
- `backend_role_arn` -> the role bound to the backend SA via Pod Identity (no Helm annotation)

## Production hardening (in the shared modules, so every environment gets it)
- **EKS**: secrets encrypted at rest (dedicated KMS key), control-plane logs to CloudWatch, API
  auth via access entries (no aws-auth ConfigMap), nodes in private subnets with IMDSv2 required
  and encrypted gp3 volumes. Public endpoint CIDRs are restrictable per env (`public_access_cidrs`).
- **VPC**: flow logs, a locked-down default security group, and an S3 gateway endpoint (private,
  free S3 access off the NAT). NAT is single (dev) or per-AZ (prod) via `single_nat_gateway`.
- **S3**: versioned, encrypted (SSE-S3 in dev, a rotating customer-managed KMS key in prod),
  public access blocked, lifecycle rules, and a TLS-only bucket policy.
- **Pod Identity** (not IRSA) for the app, the EBS CSI driver and the AWS Load Balancer
  Controller - reusable, no per-cluster OIDC.

## Notes
- Remote state in S3 with native lockfile (Terraform 1.10+, no DynamoDB); floor is 1.15.
- `dev` is cost-optimized (single NAT, small nodes, open API); `prod` is HA and hardened
  (NAT per AZ, restricted + private API, KMS-encrypted photos, cluster deletion protection).
- Applying prod: Actions -> `terraform` -> Run workflow -> environment `prod`. Read
  [`environments/prod/README.md`](environments/prod/README.md) first - `public_access_cidrs`
  is still the documentation range.
- Postgres is not here; it is a StatefulSet in the Helm chart.

