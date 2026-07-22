output "bucket_name" {
  description = "S3 Bucket Name"              # Output Description
  value       = aws_s3_bucket.terraform_backend.bucket # S3 Bucket Name
}

output "bucket_arn" {
  description = "S3 Bucket ARN"               # Output Description
  value       = aws_s3_bucket.terraform_backend.arn # S3 Bucket ARN
}

output "dynamodb_table_name" {
  description = "DynamoDB Table Name"         # Output Description
  value       = aws_dynamodb_table.terraform_locks.name # DynamoDB Table Name
}