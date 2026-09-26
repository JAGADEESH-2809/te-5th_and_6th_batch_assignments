# VPC module: a production-grade VPC for EKS - public + private subnets across AZs, an Internet
# Gateway, NAT (single for dev cost, per-AZ for HA), VPC flow logs, a locked-down default security
# group, and an S3 gateway endpoint (free; keeps S3 traffic off the NAT). Wraps the community module.

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

locals {
  # One AZ per subnet pair; the AZs are picked in order from those available in the region.
  azs = slice(data.aws_availability_zones.available.names, 0, length(var.private_subnet_cidrs))
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7" # verify currency: registry.terraform.io/modules/terraform-aws-modules/vpc/aws

  name = "${var.name_prefix}-vpc"
  cidr = var.cidr

  azs             = local.azs
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway # dev: one NAT (cheap). prod: per-AZ for HA.
  one_nat_gateway_per_az = !var.single_nat_gateway
  enable_dns_hostnames   = true
  enable_dns_support     = true

  # Lock the default security group to no rules (nothing should use it).
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  # VPC flow logs to CloudWatch (network audit trail).
  enable_flow_log                      = var.enable_flow_log
  create_flow_log_cloudwatch_iam_role  = var.enable_flow_log
  create_flow_log_cloudwatch_log_group = var.enable_flow_log
  flow_log_max_aggregation_interval    = 60
  # Retention is a real cost lever: CloudWatch keeps logs forever unless told otherwise.
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_retention_days

  # EKS needs these subnet tags for load balancer subnet discovery.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# S3 gateway endpoint: private, free access to S3 from private subnets (bypasses the NAT).
resource "aws_vpc_endpoint" "s3" {
  count             = var.enable_s3_endpoint ? 1 : 0
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3" # provider v6: .name is deprecated
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
  tags              = { Name = "${var.name_prefix}-s3-endpoint" }
}
