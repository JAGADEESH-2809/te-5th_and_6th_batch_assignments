output "role_arn" {
  description = "Role the controller assumes via Pod Identity."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Role name."
  value       = aws_iam_role.this.name
}
