output "role_arn" {
  description = "ARN of the backend role bound to the ServiceAccount via Pod Identity."
  value       = aws_iam_role.backend.arn
}
