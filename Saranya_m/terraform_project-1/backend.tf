# Remote Backend Configuration using S3 with native state locking
# S3 native locking (Terraform 1.10+) uses a lock file + S3 conditional writes.

terraform {
  backend "s3" {
    bucket       = "saranya-terraform-statefile"
    key          = "remote-backend/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true # Enable S3 native state locking
  }
}