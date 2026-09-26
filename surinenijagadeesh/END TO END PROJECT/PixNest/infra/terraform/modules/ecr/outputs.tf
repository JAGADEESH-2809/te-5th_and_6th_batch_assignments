output "repository_urls" {
  description = "Map of repository name -> repository URL."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "List of repository ARNs (used to scope the CI push policy)."
  value       = [for r in aws_ecr_repository.this : r.arn]
}
