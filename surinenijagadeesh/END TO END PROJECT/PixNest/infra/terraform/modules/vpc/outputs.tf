output "vpc_id" {
  description = "VPC id."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet ids (where EKS nodes and pods run)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet ids (for internet-facing load balancers)."
  value       = module.vpc.public_subnets
}
