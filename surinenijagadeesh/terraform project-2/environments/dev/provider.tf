# Configure Terraform and AWS Provider
terraform {
  required_version = ">= 1.5.0" # Minimum Terraform Version

  required_providers {
    aws = {
      source  = "hashicorp/aws" # AWS Provider Source
      version = "~> 5.0"        # AWS Provider Version
    }
  }
}

provider "aws" {
  region = var.aws_region # AWS Region
}