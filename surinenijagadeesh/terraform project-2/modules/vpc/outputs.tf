# VPC ID
output "vpc_id" {
  description = "VPC ID"                       # Output Description
  value       = aws_vpc.this.id                # VPC ID
}

# Public Subnet IDs
output "public_subnet_ids" {
  description = "Public Subnet IDs"            # Output Description
  value       = values(aws_subnet.public)[*].id # Public Subnet IDs
}

# Private Subnet IDs
output "private_subnet_ids" {
  description = "Private Subnet IDs"           # Output Description
  value       = values(aws_subnet.private)[*].id # Private Subnet IDs
}