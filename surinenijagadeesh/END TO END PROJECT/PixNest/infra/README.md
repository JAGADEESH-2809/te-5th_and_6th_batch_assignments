# infra - everything to deploy and operate pixnest

In an organization this would usually be its own repository. It holds all the operational code:
cloud resources, the Kubernetes package, the GitOps config, and the local run.

| Folder / file | What it is |
|---------------|------------|
| [`terraform/`](terraform/) | Cloud resources as code: reusable **modules** composed by per-**environment** roots, applied by the `terraform` GitHub Actions pipeline (keyless via OIDC). Creates the VPC, the EKS cluster, ECR, S3, the IAM roles, and Pod Identity. |
| [`helm/`](helm/) | **One chart per component** (postgres, backend, frontend - the frontend chart owns the Ingress), each with base + local + eks value files, composed by the Argo CD app-of-apps. |
| [`argocd/`](argocd/) | **Argo CD** Application manifests (GitOps): one for EKS, one for the local minikube demo. |
| [`local/`](local/) | Run the whole app on **minikube** locally (MinIO stands in for S3) - deps manifest + runbook. |
| [`platform/`](platform/) | Cluster-level manifests applied by the bootstrap script (gp3 default StorageClass). |
| [`scripts/`](scripts/) | `bootstrap-aws.sh` (stage 0, once per account: state bucket, OIDC provider, pipeline role) and `bootstrap-cluster.sh` (stage 2: StorageClass, metrics-server, AWS Load Balancer Controller, Argo CD, app-of-apps). |
| [`EKS-DEPLOY.md`](EKS-DEPLOY.md) | Ordered runbook: empty AWS account -> running app on EKS, and the teardown. |
| [`CLUSTER-ACCESS.md`](CLUSTER-ACCESS.md) | Tools to install, how EKS access entries and access policies work, and how to grant, verify and revoke kubectl access. |
| [`../docs/PLATFORM-INSTALL.md`](../docs/PLATFORM-INSTALL.md) | The platform layer installed by hand, one command at a time, with the teaching point behind each. The manual equivalent of `bootstrap-cluster.sh`. |
| `DEMO-RUNBOOK.md` | The same build as a narrated live class demo. **Instructor-only, not committed** (see `.gitignore`), so this row is intentionally not a link. |

Flow: **Terraform builds the platform (VPC, EKS, ECR, S3, roles) -> CI pushes images -> the
bootstrap script installs the AWS Load Balancer Controller + Argo CD -> Argo CD deploys from Git.** Each subfolder has its own README with the details.

