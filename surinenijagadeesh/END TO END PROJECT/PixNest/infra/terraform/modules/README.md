# modules - reusable Terraform building blocks

Each module owns one concern and is composed by the per-environment roots in
[`../environments/`](../environments/). Keeping them small and single-purpose is what makes the
setup reusable across environments.

| Module | What it creates |
|--------|-----------------|
| [`vpc/`](vpc/) | A 2-AZ VPC: public + private subnets, IGW, NAT (single or per-AZ), flow logs, S3 endpoint, EKS subnet tags. |
| [`eks/`](eks/) | The EKS cluster + managed node group + core add-ons (incl. EBS CSI via Pod Identity). |
| [`ecr/`](ecr/) | ECR repositories (scan on push, immutable tags, untagged cleanup). |
| [`s3/`](s3/) | The private, versioned photos bucket, SSE-S3 or a customer-managed KMS key. |
| [`github-oidc/`](github-oidc/) | The IAM role the app CI assumes via OIDC to push to ECR. |
| [`pod-identity/`](pod-identity/) | The backend role + EKS Pod Identity association (needs a cluster). |
| [`alb-controller/`](alb-controller/) | IAM role + Pod Identity association for the AWS Load Balancer Controller, with the published IAM policy vendored at a pinned release. |

Each module folder has its own README with inputs and outputs. No module declares a variable
default: every value is passed in from the environment's `terraform.tfvars`.
