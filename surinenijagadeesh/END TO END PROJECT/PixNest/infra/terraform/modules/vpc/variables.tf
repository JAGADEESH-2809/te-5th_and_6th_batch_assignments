variable "name_prefix" {
  description = "Name prefix for VPC resources (<name_prefix>-vpc). Distinct per environment so two environments can coexist in one account."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block."
  type        = string
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, one per AZ. EKS nodes and pods run here."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "Provide at least two private subnet CIDRs (one per AZ) for EKS high availability."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per AZ. Internet-facing load balancers live here."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.private_subnet_cidrs)
    error_message = "public_subnet_cidrs and private_subnet_cidrs must have the same length (one subnet pair per AZ)."
  }
}

variable "single_nat_gateway" {
  description = "One NAT gateway for all AZs (cheaper). false = one per AZ (HA, prod)."
  type        = bool
}

variable "enable_flow_log" {
  description = "Enable VPC flow logs to CloudWatch."
  type        = bool
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention for VPC flow logs. 0 = keep forever (billed forever)."
  type        = number
}

variable "enable_s3_endpoint" {
  description = "Create an S3 gateway VPC endpoint (free; private S3 access off the NAT)."
  type        = bool
}
