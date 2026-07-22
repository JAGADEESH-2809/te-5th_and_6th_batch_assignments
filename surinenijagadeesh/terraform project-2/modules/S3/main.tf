resource "aws_s3_bucket" "terraform_backend" {
  bucket = var.bucket_name                    # S3 Bucket Name

  tags = {
    Name        = var.bucket_name             # Bucket Name
    Environment = var.environment             # Environment Name
    Project     = var.project_name            # Project Name
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.terraform_backend.id # S3 Bucket ID

  versioning_configuration {
    status = "Enabled"                        # Enable Bucket Versioning
  }
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.dynamodb_table_name      # DynamoDB Table Name
  billing_mode = "PAY_PER_REQUEST"            # On-Demand Billing Mode
  hash_key     = "LockID"                     # Partition key

  attribute {
    name = "LockID"                           # Partition Key Name
    type = "S"                                # String Data Type
  }

  tags = {
    Name        = var.dynamodb_table_name     # Table Name
    Environment = var.environment             # Environment Name
    Project     = var.project_name            # Project Name
  }
}