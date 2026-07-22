terraform {

  required_version = ">= 1.5.0"                      # Minimum Terraform version

  required_providers {
    aws = {
      source  = "hashicorp/aws"                      # AWS Provider
      version = "~> 5.0"                             # AWS Provider version
    }
  }

}

provider "aws" {

  region = var.aws_region                            # AWS Region

}