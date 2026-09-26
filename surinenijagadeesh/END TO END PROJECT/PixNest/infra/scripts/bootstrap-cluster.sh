#!/usr/bin/env bash
# Bootstrap the platform layer on a freshly created EKS cluster, then hand over to GitOps.
#
# Stage 2 of 3:
#   1. terraform apply            -> VPC + EKS + ECR + S3 + IAM   (infra/terraform/environments/dev)
#   2. THIS SCRIPT                -> kubeconfig, admin access, StorageClass, metrics-server,
#                                   AWS Load Balancer Controller, Argo CD, repo creds
#
# To run these steps by hand in front of a class instead, see ../../docs/PLATFORM-INSTALL.md
#   3. Argo CD app-of-apps        -> postgres -> backend -> frontend, straight from Git
#
# Idempotent: safe to re-run. Requires aws, kubectl, helm, gh (logged in as the repo owner).
#
#   ./infra/scripts/bootstrap-cluster.sh [aws-profile]
set -euo pipefail

PROFILE="${1:-pixnest-boot}"
CLUSTER="${CLUSTER:-pixnest}"
REGION="${REGION:-ap-south-1}"
REPO_URL="${REPO_URL:-https://github.com/JAGADEESH-2809/te-5th_and_6th_batch_assignments.git}"
REPO_OWNER="${REPO_OWNER:-JAGADEESH-2809}"
# Keep in step with alb_controller_version in the environment tfvars: that is the release the
# vendored IAM policy in modules/alb-controller/iam_policy.json was taken from.
ALB_CHART_VERSION="${ALB_CHART_VERSION:-3.5.0}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-10.9.0}"

say() { printf "\n=== %s ===\n" "$1"; }

say "1/8 kubeconfig for $CLUSTER"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" --profile "$PROFILE" >/dev/null
echo "kubeconfig updated"

say "2/8 cluster-admin access entry for the caller"
CALLER_ARN=$(aws sts get-caller-identity --profile "$PROFILE" --query Arn --output text)
# Terraform creates the cluster as the pipeline role, so the human operator needs their own entry.
aws eks create-access-entry --cluster-name "$CLUSTER" --principal-arn "$CALLER_ARN" \
  --profile "$PROFILE" >/dev/null 2>&1 || echo "access entry already exists"
aws eks associate-access-policy --cluster-name "$CLUSTER" --principal-arn "$CALLER_ARN" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster --profile "$PROFILE" >/dev/null 2>&1 || echo "policy already associated"
kubectl get nodes

say "3/8 default StorageClass (gp3 on the EBS CSI driver)"
# EKS still ships a legacy gp2 class using the in-tree provisioner, which Kubernetes 1.31+
# removed - PVCs against it hang forever. Install gp3 as the default and de-default gp2.
kubectl apply -f "$(dirname "$0")/../platform/storageclass.yaml"
kubectl patch storageclass gp2 \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' \
  >/dev/null 2>&1 || true
kubectl get storageclass

say "4/8 metrics-server"
# Kubernetes ships no metrics pipeline. Without this `kubectl top` fails and every HPA reports
# cpu: <unknown> and never scales - which makes Argo CD show the backend as Degraded.
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm repo update metrics-server >/dev/null
helm upgrade --install metrics-server metrics-server/metrics-server   -n kube-system --wait --timeout 5m >/dev/null
echo "metrics-server ready"

say "5/8 AWS Load Balancer Controller (turns the app Ingress into a real ALB)"
# Its AWS permissions come from the IAM role + Pod Identity association that Terraform created
# (modules/alb-controller), so the ServiceAccount needs no annotation here.
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --profile "$PROFILE" \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update eks >/dev/null
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --version "$ALB_CHART_VERSION" \
  --set clusterName="$CLUSTER" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --wait --timeout 10m >/dev/null
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller --timeout=300s >/dev/null
echo "aws-load-balancer-controller ready (vpc $VPC_ID)"

say "6/8 Argo CD"
# The Helm chart rather than the published install.yaml: the version is pinned, settings live in a
# reviewable values file, and helm history/rollback/uninstall all work. That values file creates
# NO Ingress - reach the UI with port-forward (see the notes printed at the end).
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  --version "$ARGOCD_CHART_VERSION" \
  -f "$(dirname "$0")/../platform/argocd/values.yaml" \
  --wait --timeout 10m >/dev/null
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

say "7/8 repository credential (read-only deploy key)"
# A deploy key, not `gh auth token`. The token is a PERSON: broad scope across every repo that
# account can reach, dies when they leave, and returns whichever gh account happens to be active.
# A deploy key is scoped to this one repository and marked read-only, so even a compromised
# cluster cannot rewrite the source of truth. See docs/GIT-REPO-ACCESS.md.
KEY_FILE="${KEY_FILE:-$HOME/.ssh/argocd_${REPO_OWNER}_$(basename "$REPO_URL" .git)}"
REPO_SLUG="${REPO_OWNER}/$(basename "$REPO_URL" .git)"

if [ ! -f "$KEY_FILE" ]; then
  echo "generating a read-only deploy key at $KEY_FILE"
  mkdir -p "$(dirname "$KEY_FILE")"
  ssh-keygen -t ed25519 -C "argocd@${REPO_SLUG}" -f "$KEY_FILE" -N "" -q
  # Registering it needs admin on the repo. gh must be the account that owns it.
  if ! gh api "repos/${REPO_SLUG}" >/dev/null 2>&1; then
    echo "ERROR: the active gh account cannot see ${REPO_SLUG}." >&2
    echo "       Run: gh auth switch --user ${REPO_OWNER}" >&2
    echo "       Or add $KEY_FILE.pub as a read-only deploy key by hand and re-run." >&2
    exit 1
  fi
  gh api "repos/${REPO_SLUG}/keys" -X POST \
    -f title="argocd (read-only, added by bootstrap-cluster.sh)" \
    -f key="$(cat "$KEY_FILE.pub")" \
    -F read_only=true >/dev/null
  echo "deploy key registered on ${REPO_SLUG} (read-only)"
else
  echo "reusing the existing deploy key at $KEY_FILE"
fi

# The URL must be the SSH form: Argo CD matches a credential to a repo by URL string, so an SSH
# key does not apply to an https:// Application.
kubectl -n argocd create secret generic pixnest-repo \
  --from-literal=type=git \
  --from-literal=url="git@github.com:${REPO_SLUG}.git" \
  --from-file=sshPrivateKey="$KEY_FILE" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n argocd label secret pixnest-repo \
  argocd.argoproj.io/secret-type=repository --overwrite >/dev/null
echo "repo credential configured (deploy key, private key not printed)"

say "8/8 hand over to GitOps (app-of-apps)"
kubectl apply -f "$(dirname "$0")/../argocd/application.yaml"

cat <<'EOF'

Bootstrap complete. Argo CD is now deploying postgres -> backend -> frontend from Git.

Watch it:
  kubectl -n argocd get applications
  kubectl -n pixnest get pods -w

Get the public URL (the LB takes a minute to come up):
  kubectl -n pixnest get ingress pixnest \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

Argo CD UI (admin password):
  kubectl -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode}}'
  # 8080:443 serves TLS here (plain manifest install). With the Helm chart and
  # server.insecure: true, use 8080:80 and http:// instead.
  kubectl -n argocd port-forward svc/argocd-server 8080:443
EOF




