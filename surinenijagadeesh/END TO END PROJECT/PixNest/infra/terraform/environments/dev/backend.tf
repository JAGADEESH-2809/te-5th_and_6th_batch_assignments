# Remote state for the dev environment. Each environment has its own state key.
#
# This is a PARTIAL backend config: bucket and region are deliberately NOT hardcoded, because
# the state bucket is one of the three things that must exist BEFORE Terraform can run at all
# (see infra/scripts/bootstrap-aws.sh). Its name is account-specific, so it is supplied at
# init time - exactly like the OIDC role ARN is supplied to the pipeline as a repo variable:
#
#   pipeline:  terraform init -backend-config="bucket=${{ vars.TF_STATE_BUCKET }}" \
#                             -backend-config="region=${{ vars.AWS_REGION }}"
#   locally:   terraform init -reconfigure \
#                -backend-config="bucket=pixnest-tfstate-$(aws sts get-caller-identity \
#                                          --query Account --output text)" \
#                -backend-config="region=ap-south-1"
#
# Terraform backends cannot use variables or interpolation, so -backend-config is the
# supported way to keep an account identifier out of version control.
terraform {
  backend "s3" {
    key          = "env/dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}


