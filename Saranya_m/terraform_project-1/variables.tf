variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
}

variable "availability_zone" {
  description = "Availability Zone for the subnets and EC2 instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for web and database servers"
  type        = string
}

variable "my_ip" {
  description = "My public IP address"
  type        = string
}

variable "owner" {
  description = "Owner tag value applied to all resources"
  type        = string
}

variable "environment" {
  description = "Environment tag value (e.g., dev, test, prod)"
  type        = string
}

variable "key_name" {
  description = "Name of the AWS EC2 Key Pair used for SSH access"
  type        = string
  default     = ""
}