output "role_arn" {
  description = "ARN of the CI role (set as GitHub repo variable AWS_GHA_ROLE_ARN)."
  value       = aws_iam_role.gha.arn
}
