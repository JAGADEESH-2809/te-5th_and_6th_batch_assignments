# Remote state for the prod environment - isolated from dev by its own state key.
# Partial backend config: bucket and region come from -backend-config at init time.
# See ../dev/backend.tf for why, and infra/scripts/bootstrap-aws.sh for who creates the bucket.
terraform {
  backend "s3" {
    key          = "env/prod/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
