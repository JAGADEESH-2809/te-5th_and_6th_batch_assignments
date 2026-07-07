aws_region        = "ap-south-1"
project_name      = "terraform-remote-backend-demo"
vpc_cidr           = "10.0.0.0/16"
public_subnet_cidr = "10.0.1.0/24"
instance_type      = "t3.micro"
allowed_ssh_cidr   = ["0.0.0.0/0"] # Restrict to your IP: ["YOUR.IP.ADDRESS/32"]
ami_id             = "ami-0bc7aabcf58d1e02a"
availability_zone  = "ap-south-1a"
