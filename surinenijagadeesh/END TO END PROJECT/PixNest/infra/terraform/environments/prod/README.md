# Environment: prod

The production environment. Same modules as `dev`, configured for high availability, retention
and blast-radius control, with its own isolated state (`env/prod/terraform.tfstate`).

It has **not been applied yet**, but it is no longer a sketch: `terraform validate` and
`terraform plan` both pass against the real backend, and every resource it creates has a name
that does not collide with dev.

## Why `name_prefix` exists

In a real organisation prod lives in its own AWS account and names can repeat freely. It does not
here - dev and prod share account `359367063384` - and three kinds of name are account-global or
account-unique:

| Resource | Name | Would collide? |
|----------|------|----------------|
| IAM roles | `<name_prefix>-gha`, `<name_prefix>-backend`, `<cluster_name>-ebs-csi` | yes, account-global |
| ECR repositories | `<name_prefix>-backend`, `<name_prefix>-frontend` | yes, unique per account+region |
| S3 photos bucket | `<name_prefix>-photos-<account>` | yes, globally unique |

So dev sets `name_prefix = "pixnest"` (keeping the names the Helm overlays already expect) and
prod sets `name_prefix = "pixnest-prod"`. Without that, `terraform apply` on prod fails with
`EntityAlreadyExists` and `RepositoryAlreadyExists`.

## How prod differs from dev

All of it lives in `terraform.tfvars`; there are no defaults anywhere to fall back on.

| Setting | dev | prod | Why |
|---------|-----|------|-----|
| NAT gateways | one, shared | one per AZ | no single point of failure |
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` | non-overlapping, so the two could be peered |
| API endpoint | public, `0.0.0.0/0` | public but CIDR-restricted, **and** private inside the VPC | reachable for operators, closed to everyone else |
| Cluster deletion protection | off | **on** | `destroy` refuses until it is deliberately turned off |
| Control-plane logs | `api`, `authenticator`, 7 days | all five types, 90 days | audit trail; audit logs are high volume, hence the split |
| Flow log retention | 7 days | 90 days | network forensics |
| Nodes | 2x `c7i-flex.large`, min 1 | 2x `c7i-flex.large`, min 2 | survives losing a node. **Minimal on purpose** - see below |
| Node disk | 30 GiB | 30 GiB | no workload yet, so no image bloat to hold |
| Photos encryption | SSE-S3 (free) | **customer-managed KMS key**, rotating yearly, Bucket Keys on | auditable, revocable key; Bucket Keys keep KMS request cost near zero |
| Old object versions | 30 days | 365 days | recovery window |
| ECR `force_delete` | true | **false** | destroy must never throw away deployable artifacts |
| S3 `force_destroy` | true | **false** | destroy must never delete production photos |

When the bucket uses KMS, S3 permissions alone are not enough - the backend role also gets
`kms:Decrypt` and `kms:GenerateDataKey` on that one key, conditioned on S3 being the caller. The
`pod-identity` module adds that statement automatically when a key ARN is passed in.

## Node sizing is minimal until there is a workload

prod runs two `c7i-flex.large` nodes, not three `m5.large`, because nothing is deployed to it
yet. The type is also constrained: this AWS account may only launch free-tier-eligible instance
types, and `c7i-flex.large` is the closest eligible match to the `t3.medium` this project was
built on. Size is a floor rather than a preference: pod density is capped by ENIs, and a
`t3.small` tops out near 11 pods, which the platform layer alone (aws-node, kube-proxy, CoreDNS,
EBS CSI, the AWS Load Balancer Controller, Argo CD) would consume before one application pod
could schedule. Two
nodes across two AZs keeps a node failure survivable. Restore `["m5.large"]` with desired/min 3, max 6
and 50 GiB when real traffic arrives and the account can launch it; it is one tfvars edit and a
pipeline apply.

Worth being clear about what this does and does not save. Node hours are not the dominant cost of
an idle prod environment - the EKS control plane bills per cluster-hour whether or not anything
runs on it, and prod deliberately runs one NAT gateway per AZ, which bills per hour each. The
cheapest idle prod is one that has not been applied.

## Before the first apply

1. **Check `public_access_cidrs` still matches you.** It holds the operator's public address as
   a `/32`, set on 2026-09-10. That is a dynamic residential IP: once it changes, nothing reaches
   the cluster API and the fix is to edit the tfvars and apply. `curl -s https://checkip.amazonaws.com`
   prints the current one. A static office or VPN range is the durable answer.
2. **Know what gates the apply.** Applying to prod requires typing `prod` into the workflow's
   `confirm` input. The stronger gate - GitHub *required reviewers*, where a second person clicks
   approve - needs GitHub Pro or Team on a private repo; this repo is on Free, so the rule cannot
   be created yet. The `prod` GitHub Environment already exists and the apply job references it,
   so adding reviewers later takes effect immediately.
3. Decide whether prod should share this AWS account at all. If not, run
   `infra/scripts/bootstrap-aws.sh` against the new account and set the `AWS_TF_ROLE_ARN_PROD` and
   `TF_STATE_BUCKET_PROD` repo variables; the pipeline picks them up with no code change.

## Apply

Through the pipeline: **Actions -> `terraform` -> Run workflow -> environment `prod`, action
`apply`**. The plan is uploaded as an artifact and the apply job applies that exact plan.

Locally, if you must:

```bash
cd infra/terraform/environments/prod
terraform init -reconfigure \
  -backend-config="bucket=pixnest-tfstate-$(aws sts get-caller-identity --query Account --output text)" \
  -backend-config="region=ap-south-1"
terraform plan
```

## Destroy

Two deliberate steps, by design. Set `cluster_deletion_protection = false`, apply that, and only
then run the destroy - which additionally requires typing `prod` into the workflow's `confirm`
input. Delete Kubernetes-created load balancers and PVCs first, as in
[../../../EKS-DEPLOY.md](../../../EKS-DEPLOY.md).

## What prod does not have yet

The Helm overlays (`values-eks.yaml`) and the Argo CD app-of-apps still point at the dev
registry, the dev bucket and one cluster. Deploying the **application** to prod needs a second
Argo CD tree with prod values; the Terraform layer below it is ready.


