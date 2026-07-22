# -----------------------------
# VPC ID
# -----------------------------
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

# -----------------------------
# Public Subnet IDs
# -----------------------------
output "public_subnet_ids" {
  description = "Public Subnet IDs"
  value       = module.vpc.public_subnet_ids
}

# -----------------------------
# Private Subnet IDs
# -----------------------------
output "private_subnet_ids" {
  description = "Private Subnet IDs"
  value       = module.vpc.private_subnet_ids
}

# -----------------------------
# Security Group ID
# -----------------------------
output "security_group_id" {
  description = "Security Group ID"
  value       = module.ec2.security_group_id
}

# -----------------------------
# EC2 Instance IDs
# -----------------------------
output "instance_ids" {
  description = "EC2 Instance IDs"
  value       = module.ec2.instance_ids
}

# -----------------------------
# Public IP Addresses
# -----------------------------
output "public_ips" {
  description = "Public IP Addresses"
  value       = module.ec2.public_ips
}

# -----------------------------
# Website URL
# -----------------------------
output "website_url" {
  description = "Website URL"

  value = [
    for ip in module.ec2.public_ips :
    "http://${ip}"
  ]
}

# -----------------------------
# Environment
# -----------------------------
output "environment" {
  description = "Deployment Environment"
  value       = var.environment
}

# -----------------------------
# AWS Region
# -----------------------------
output "aws_region" {
  description = "AWS Region"
  value       = var.aws_region
}