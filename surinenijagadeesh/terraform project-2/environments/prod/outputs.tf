output "vpc_id" {

  value = module.vpc.vpc_id                          # VPC ID

}

output "public_subnet_ids" {

  value = module.vpc.public_subnet_ids               # Public Subnet IDs

}

output "private_subnet_ids" {

  value = module.vpc.private_subnet_ids              # Private Subnet IDs

}

output "instance_ids" {

  value = module.ec2.instance_ids                    # EC2 Instance IDs

}

output "public_ips" {

  value = module.ec2.public_ips                      # EC2 Public IPs

}

output "security_group_id" {

  value = module.ec2.security_group_id               # Security Group ID

}
output "website_url" {

  value = [
    for ip in module.ec2.public_ips :
    "http://${ip}"
  ]

}