# Deploy pixnest to EKS (runbook)

From an empty AWS account to the running app, in the order things must happen. This is the
operational version; the narrated class version of the same build, with talking points and a
troubleshooting table, is the instructor-only demo runbook (not committed; see `.gitignore`).
To install the platform layer by hand, see [../docs/PLATFORM-INSTALL.md](../docs/PLATFORM-INSTALL.md).

Current target: account `359367063384`, `ap-south-1`, cluster `pixnest`, Terraform environment
`dev`. Nothing account-specific is committed to the repo: the account id reaches the pipelines
through GitHub repo variables, and reaches the app through the two `values-eks.yaml` overlays
(see step 4).

| Stage | Runs | Creates | Time |
|-------|------|---------|------|
| 0 | `scripts/bootstrap-aws.sh` (once per account, admin creds) | TF state bucket, GitHub OIDC provider, `pixnest-tf` role, repo variables | ~1 min |
| 1 | `terraform` GitHub Actions workflow | VPC, EKS, ECR, S3, app IAM | ~18 min |
| 1b | `ci` GitHub Actions workflow | images in ECR + GitOps tag bump | ~3 min |
| 2 | `scripts/bootstrap-cluster.sh` | StorageClass, metrics-server, AWS Load Balancer Controller, Argo CD, repo credential, app-of-apps | ~4 min |
| 3 | Argo CD (nothing to run) | postgres -> backend -> frontend, from Git | ~2 min |

Tools on the laptop: `aws`, `kubectl`, `helm`, `gh` (logged in as the repo owner, `JAGADEESH-2809`).
Set the admin profile explicitly and clear any stale env credentials first, or the AWS CLI and
Terraform pick up the env vars and fail with `InvalidClientTokenId`:

```bash
export AWS_PROFILE=pixnest-boot
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
aws sts get-caller-identity
```

## 0. Bootstrap the account (once - already done for the current account)

```bash
./infra/scripts/bootstrap-aws.sh pixnest-boot
```

Creates exactly the three things Terraform cannot create for itself, and sets the repo variables
the pipelines read (`AWS_ACCOUNT_ID`, `AWS_REGION`, `AWS_TF_ROLE_ARN`, `AWS_GHA_ROLE_ARN`,
`TF_STATE_BUCKET`):

1. S3 state bucket `pixnest-tfstate-<account>` (versioned, encrypted, private)
2. the GitHub OIDC identity provider
3. IAM role `pixnest-tf`, trusted only by workflows in this repo

These are kept between teardowns. Re-running the script is idempotent.

To create these by hand instead of running the script, or to understand each policy the
project uses, see [`../docs/IAM-ROLES-AND-POLICIES.md`](../docs/IAM-ROLES-AND-POLICIES.md).

Trust-policy gotcha: this GitHub account emits immutable-id subject claims
(`repo:JAGADEESH-2809@<id>/pixnest@<id>:...`), so the role trusts `repo:JAGADEESH-2809@*/pixnest@*:*`.
The plain `repo:owner/name:*` pattern fails with "Not authorized to perform
sts:AssumeRoleWithWebIdentity". The script and the Terraform `github_repo` variable both use
the wildcard form.

## 1. Build the AWS environment (Terraform pipeline, ~18 min)

GitHub -> Actions -> `terraform` -> Run workflow -> environment `dev`, action `apply`. The run assumes
`pixnest-tf` via OIDC, inits against the S3 backend (`-backend-config` from the repo
variables, since `backend.tf` is a partial backend), plans, and applies
`infra/terraform/environments/dev`:

- VPC: 2 AZs, public + private subnets, a single NAT gateway in dev
- EKS 1.36 (`module.eks`): API authentication mode, KMS-encrypted secrets, control-plane logs,
  an AL2023 managed node group (`t3.medium`, IMDSv2, encrypted gp3 root), and the add-ons
  coredns, kube-proxy, vpc-cni, eks-pod-identity-agent, aws-ebs-csi-driver (its AWS
  permissions come from a Pod Identity association, not IRSA)
- ECR `pixnest-backend` and `pixnest-frontend` (immutable tags, scan on push)
- IAM role + Pod Identity association for the **AWS Load Balancer Controller**, so the controller
  can create ALBs without any stored credential
- S3 photos bucket `pixnest-photos-<account>` (private, versioned, TLS-only). The name is
  derived from the account id on purpose, so a destroy + apply reproduces the same name and the
  Helm overlay stays valid
- IAM: `pixnest-gha` (CI pushes to ECR via OIDC) and `pixnest-backend` (S3 access for the
  backend pod), plus the Pod Identity association (namespace `pixnest`, ServiceAccount `pixnest-backend`) -> role `pixnest-backend`

`terraform.tfvars` already sets `cluster_name = "pixnest"` and `enable_pod_identity = true`.

Note that a push to `main` touching `infra/terraform/**` (README files excepted) also applies -
to **dev only**; prod is always a deliberate dispatch. Make infra changes on a PR, where the
pipeline plans both environments and posts each plan as a comment, then merge.

For prod, read [`terraform/environments/prod/README.md`](terraform/environments/prod/README.md)
first: it needs a real `public_access_cidrs` value, and its cluster has deletion protection on.

Local alternative, same state, same partial-backend values:

```bash
cd infra/terraform/environments/dev
terraform init -reconfigure \
  -backend-config="bucket=pixnest-tfstate-<account>" -backend-config="region=ap-south-1"
terraform plan
```

## 1b. Fill ECR (after a teardown)

`terraform destroy` removes the ECR repositories and their images, so after a rebuild the
registries are empty and the pods would sit in `ImagePullBackOff`. Run the `ci` workflow once
(GitHub -> Actions -> `ci` -> Run workflow, or push a commit). It builds, scans, and pushes both
images and commits the new tags into the Helm values (the GitOps bump).

## 2. Platform layer on the cluster (~4 min)

```bash
./infra/scripts/bootstrap-cluster.sh pixnest-boot
```

In order: kubeconfig for `pixnest`; a cluster-admin access entry for the caller (Terraform
created the cluster as the pipeline role, so the human operator needs their own entry - see
[CLUSTER-ACCESS.md](CLUSTER-ACCESS.md) for what that means and how to do it by hand); the gp3
default StorageClass from `platform/storageclass.yaml` (EKS still ships a legacy gp2 class on the
in-tree provisioner that Kubernetes 1.31+ removed, so PVCs against it hang forever); metrics-server;
the AWS Load Balancer Controller (which builds the ALB once an Ingress exists); Argo CD (server-side apply); an Argo CD repository
credential built from `gh auth token` (the repo is private); and finally the app-of-apps root
`argocd/application.yaml`. Idempotent, safe to re-run.

## 3. GitOps takes over (~2 min, nothing to run)

Argo CD syncs `infra/argocd/apps/` in sync-wave order: `pixnest-postgres` (wave 0) ->
`pixnest-backend` (wave 1) -> `pixnest-frontend` (wave 2). Each Application renders its chart
with `values.yaml` + `values-eks.yaml`.

```bash
kubectl -n argocd get applications -w
kubectl -n pixnest get pods,svc,ingress,hpa,pvc
kubectl -n pixnest get ingress pixnest \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'   # the public URL (the ALB)
```

Open the URL, register, log in, upload a photo. The object lands in S3 through Pod Identity (no
keys in the pod, no ServiceAccount annotation); the metadata lands in the Postgres StatefulSet on
an EBS volume. Swagger is off on EKS (`exposeDocs: false`).

Argo CD UI, if wanted:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode}}'
# 8080:443 because this install serves TLS. If you installed the Helm chart with
# server.insecure: true, use 8080:80 and http:// instead.
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

## 4. Pointing at a different AWS account

Only two files carry account-specific values, and both follow the deterministic names Terraform
produces (`terraform output` in `environments/dev` prints them):

- `helm/backend/values-eks.yaml`: `image.repository` (ECR URL) and `env.S3_BUCKET`
- `helm/frontend/values-eks.yaml`: `image.repository` (ECR URL)

Everything else (state bucket, role ARNs, region) comes from the repo variables that
`bootstrap-aws.sh` sets. Run stage 0 against the new account, update those two overlays, then
continue from stage 1.

## Teardown (stop the spend)

Order matters. Kubernetes creates real AWS resources that are not in Terraform state (the
ingress load balancer and its security group, the EBS volumes behind PVCs), and they block the
VPC delete with `DependencyViolation`.

1. Let Kubernetes remove its own AWS resources. The ALB belongs to the **Ingress**, so
   deleting Services alone is not enough:
   ```bash
   kubectl delete ingress -A --all
   kubectl delete svc -A --field-selector spec.type=LoadBalancer
   kubectl -n pixnest delete pvc --all
   ```
2. GitHub -> Actions -> `terraform` -> Run workflow -> environment `dev`, action `destroy`, and
   type `dev` into the `confirm` box. Removes everything Terraform owns: VPC, NAT, EKS + nodes,
   ECR (and images), the photos bucket, the app roles.
3. Stage 0 stays (state bucket, OIDC provider, `pixnest-tf`); it costs nothing and is needed
   for the next build.

If the cluster is already gone and the destroy fails, delete the orphaned classic ELB and its
`k8s-elb-<name>` security group by hand; the exact commands are in
the Teardown section below.

## If something goes wrong

See the symptom -> cause -> fix table at the end of the instructor-only demo runbook.

## Notes

- Postgres is a StatefulSet on an EBS-backed PVC, pinned to one AZ, in every environment. For
  production durability use a database operator (CloudNativePG) or managed RDS/Aurora.
- Auth to AWS is EKS Pod Identity throughout (app and EBS CSI driver), not IRSA; the cluster has
  no OIDC provider and the ServiceAccounts carry no annotations.
- Argo CD is deliberately not installed by Terraform: Terraform owns cloud resources, the
  bootstrap script owns the in-cluster platform layer, and Git owns the app.


