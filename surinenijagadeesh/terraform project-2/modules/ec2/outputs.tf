# -----------------------------
# Security Group ID
# -----------------------------
output "security_group_id" {
  description = "Security Group ID"
  value       = aws_security_group.this.id
}

# -----------------------------
# EC2 Instance IDs
# -----------------------------
output "instance_ids" {
  description = "EC2 Instance IDs"
  value       = aws_instance.this[*].id
}

# -----------------------------
# Public IP Addresses
# -----------------------------
output "public_ips" {
  description = "Public IP Addresses"
  value       = aws_instance.this[*].public_ip
}