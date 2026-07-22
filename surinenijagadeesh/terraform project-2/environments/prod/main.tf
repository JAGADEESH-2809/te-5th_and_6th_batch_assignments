# VPC Module
module "vpc" {

  source = "../../modules/vpc"                        # VPC Module Path

  project_name    = var.project_name                  # Project Name
  vpc_cidr        = var.vpc_cidr                      # VPC CIDR
  public_subnets  = var.public_subnets                # Public Subnet Details
  private_subnets = var.private_subnets               # Private Subnet Details
  environment     = var.environment                   # Environment Name

}

# EC2 Module
module "ec2" {

  source = "../../modules/ec2"                        # EC2 Module Path

  project_name   = var.project_name                   # Project Name
  vpc_id         = module.vpc.vpc_id                  # VPC ID
  subnet_id      = module.vpc.public_subnet_ids[0]    # First Public Subnet
  environment    = var.environment                    # Environment Name
  instance_type  = var.instance_type                  # EC2 Instance Type
  instance_count = var.instance_count                 # Number of EC2 Instances
  allowed_ssh_ip = var.allowed_ssh_ip                 # SSH Allowed IP
  key_name       = var.key_name                       # EC2 Key Pair

}