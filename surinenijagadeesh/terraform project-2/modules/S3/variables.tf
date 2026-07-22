variable "project_name" {
  description = "Project Name"                # Project Name
  type        = string                        # Variable Type
}

variable "environment" {
  description = "Environment Name"            # Environment (dev/prod)
  type        = string                        # Variable Type
}

variable "bucket_name" {
  description = "S3 Bucket Name"              # S3 Bucket Name
  type        = string                        # Variable Type
}

variable "dynamodb_table_name" {
  description = "DynamoDB Table Name"         # DynamoDB Table Name
  type        = string                        # Variable Type
}