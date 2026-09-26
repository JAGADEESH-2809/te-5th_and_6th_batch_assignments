output "bucket" {
  description = "Photos bucket name (Helm backend.env.S3_BUCKET)."
  value       = aws_s3_bucket.photos.bucket
}

output "bucket_arn" {
  description = "Photos bucket ARN (scopes the backend's least-privilege S3 policy)."
  value       = aws_s3_bucket.photos.arn
}

output "kms_key_arn" {
  description = "KMS key protecting the objects, or null when the bucket uses SSE-S3. The backend role needs kms:Decrypt/GenerateDataKey on it."
  value       = var.create_kms_key ? aws_kms_key.photos[0].arn : null
}
