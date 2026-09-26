terraform {
  # 1.10+ for the S3 native state lockfile; floor set to the current minor.
  required_version = ">= 1.15"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.64" # verify currency: registry.terraform.io/providers/hashicorp/aws
    }
  }
}
