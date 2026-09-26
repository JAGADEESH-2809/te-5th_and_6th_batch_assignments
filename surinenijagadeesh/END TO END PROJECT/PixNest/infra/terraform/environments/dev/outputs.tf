output "ecr_backend_url" {
  description = "Backend ECR repository URL (Helm backend.image.repository)."
  value       = module.ecr.repository_urls["${var.name_prefix}-backend"]
}

output "ecr_frontend_url" {
  description = "Frontend ECR repository URL (Helm frontend.image.repository)."
  value       = module.ecr.repository_urls["${var.name_prefix}-frontend"]
}

output "s3_bucket" {
  description = "Photos bucket name (Helm backend.env.S3_BUCKET)."
  value       = module.s3.bucket
}

output "s3_kms_key_arn" {
  description = "KMS key encrypting the photos, or null when the bucket uses SSE-S3."
  value       = module.s3.kms_key_arn
}

output "github_actions_role_arn" {
  description = "CI role ARN (GitHub repo variable AWS_GHA_ROLE_ARN)."
  value       = module.github_oidc.role_arn
}

output "backend_role_arn" {
  description = "Backend role bound via Pod Identity. Null until enable_pod_identity."
  value       = var.enable_pod_identity ? module.pod_identity[0].role_arn : null
}

output "alb_controller_role_arn" {
  description = "Role the AWS Load Balancer Controller assumes via Pod Identity. Null when disabled."
  value       = var.enable_alb_controller ? module.alb_controller[0].role_arn : null
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_access_entries" {
  description = "IAM principals granted access to the Kubernetes API by this configuration (the pipeline role is granted by the module and not listed)."
  value       = { for k, v in var.access_entries : k => v.principal_arn }
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "vpc_id" {
  description = "VPC id."
  value       = module.vpc.vpc_id
}
