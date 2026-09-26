#!/usr/bin/env bash
# STAGE 0: bootstrap an EMPTY AWS account so the Terraform pipeline can take over.
#
# The chicken-and-egg problem of Infrastructure as Code: Terraform needs somewhere to store
# state, and GitHub Actions needs permission to run Terraform - but neither can exist yet.
# So exactly three things are created ONCE, by hand, with admin credentials:
#
#   1. an S3 bucket for Terraform remote state   (versioned, encrypted, private)
#   2. the GitHub OIDC identity provider          (so Actions can authenticate with no keys)
#   3. the pixnest-tf IAM role                  (what the pipeline assumes to build everything)
#
# Everything else - VPC, EKS, ECR, S3, app IAM - is created by Terraform through the pipeline.
# This script is idempotent: safe to re-run.
#
#   ./infra/scripts/bootstrap-aws.sh [aws-profile]
set -euo pipefail

PROFILE="${1:-pixnest-boot}"
REGION="${REGION:-ap-south-1}"
REPO="${REPO:-JAGADEESH-2809/te-5th_and_6th_batch_assignments}"
REPO_OWNER="${REPO%%/*}"
REPO_NAME="${REPO##*/}"

say() { printf "\n=== %s ===\n" "$1"; }

say "0/5 who am I?"
ACCOUNT=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
echo "account: $ACCOUNT   region: $REGION   repo: $REPO"
BUCKET="pixnest-tfstate-${ACCOUNT}"
OIDC_ARN="arn:aws:iam::${ACCOUNT}:oidc-provider/token.actions.githubusercontent.com"
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/pixnest-tf"

say "1/5 Terraform state bucket: $BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" --profile "$PROFILE" 2>/dev/null; then
  echo "already exists"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" --profile "$PROFILE" >/dev/null
  echo "created"
fi
aws s3api put-bucket-versioning --bucket "$BUCKET" --profile "$PROFILE" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" --profile "$PROFILE" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" --profile "$PROFILE" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo "versioned, encrypted, private"

say "2/5 GitHub OIDC identity provider"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" \
     --profile "$PROFILE" >/dev/null 2>&1; then
  echo "already exists"
else
  aws iam create-open-id-connect-provider --profile "$PROFILE" \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
                      1c58a3a8518e8759bf075b76b750d4f2df264fcd >/dev/null
  echo "created"
fi

say "3/5 pixnest-tf role (assumed by the Terraform pipeline via OIDC)"
# NOTE: this account emits IMMUTABLE-ID subject claims (repo:login@id/repo@id:...), so the
# trust condition uses @* wildcards. A plain repo:owner/name:* pattern silently fails here.
TRUST=$(cat <<JSON
{"Version":"2012-10-17","Statement":[{
  "Effect":"Allow",
  "Principal":{"Federated":"$OIDC_ARN"},
  "Action":"sts:AssumeRoleWithWebIdentity",
  "Condition":{
    "StringEquals":{"token.actions.githubusercontent.com:aud":"sts.amazonaws.com"},
    "StringLike":{"token.actions.githubusercontent.com:sub":"repo:${REPO_OWNER}@*/${REPO_NAME}@*:*"}
  }}]}
JSON
)
if aws iam get-role --role-name pixnest-tf --profile "$PROFILE" >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name pixnest-tf \
    --policy-document "$TRUST" --profile "$PROFILE"
  echo "trust policy updated"
else
  aws iam create-role --role-name pixnest-tf --assume-role-policy-document "$TRUST" \
    --description "GitHub Actions Terraform pipeline (OIDC)" --profile "$PROFILE" >/dev/null
  echo "created"
fi
# Terraform manages VPC/EKS/IAM/ECR/S3, so it needs broad rights. The blast radius is bounded
# by the trust policy: only workflows in THIS repo can assume it.
aws iam attach-role-policy --role-name pixnest-tf \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess --profile "$PROFILE"
echo "AdministratorAccess attached"

say "4/5 GitHub repo variables (so the pipelines know where to go)"
gh variable set AWS_ACCOUNT_ID   --body "$ACCOUNT"  --repo "$REPO"
gh variable set AWS_REGION       --body "$REGION"   --repo "$REPO"
gh variable set AWS_TF_ROLE_ARN  --body "$ROLE_ARN" --repo "$REPO"
# The state bucket name is account-specific, so it is NOT hardcoded in backend.tf - the
# pipeline passes it to `terraform init -backend-config`. Same idea as the role ARN: nothing
# account-specific is committed, so this repo runs against any AWS account unchanged.
gh variable set TF_STATE_BUCKET  --body "$BUCKET"   --repo "$REPO"
# pixnest-gha is created BY Terraform; its ARN is deterministic, so set it now.
gh variable set AWS_GHA_ROLE_ARN --body "arn:aws:iam::${ACCOUNT}:role/pixnest-gha" --repo "$REPO"
gh variable list --repo "$REPO"

say "5/5 done"
cat <<EOF

Bootstrap complete. The account can now build itself.

Next (stage 1) - run the infra pipeline, no credentials needed anywhere:
  GitHub -> Actions -> "terraform" -> Run workflow

  (or locally, passing the same partial-backend values the pipeline uses:
     cd infra/terraform/environments/dev
     terraform init -reconfigure -backend-config="bucket=$BUCKET" -backend-config="region=$REGION"
     terraform apply)

That creates the VPC, EKS cluster, ECR, S3 and app IAM roles - about 18 minutes.
EOF


