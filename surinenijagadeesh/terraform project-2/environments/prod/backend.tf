terraform {

  backend "s3" {

    bucket         = "jagadeesh-terraform-project-2"   # S3 Bucket
    key            = "prod/terraform.tfstate"          # Production State file
    region         = "ap-south-1"                      # AWS Region
    dynamodb_table = "terraform-locks"                 # Lock table
    encrypt        = true                              # Encrypt state

  }

}