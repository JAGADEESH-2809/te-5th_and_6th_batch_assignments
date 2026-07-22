# AWS Region
variable "aws_region" {
  description = "AWS Region" # AWS Region
  type        = string       # String Variable
}

# Project Name
variable "project_name" {
  description = "Project Name" # Project Name
  type        = string         # String Variable
}

# Environment Name
variable "environment" {
  description = "Environment Name" # Environment Name
  type        = string             # String Variable
}

# VPC CIDR Block
variable "vpc_cidr" {
  description = "VPC CIDR Block" # VPC CIDR Block
  type        = string           # String Variable
}

# Public Subnets
variable "public_subnets" {
  description = "Public Subnet Configuration" # Public Subnet Details

  type = map(object({
    cidr = string # CIDR Block
    az   = string # Availability Zone
  }))
}

# Private Subnets
variable "private_subnets" {
  description = "Private Subnet Configuration" # Private Subnet Details

  type = map(object({
    cidr = string # CIDR Block
    az   = string # Availability Zone
  }))
}

# EC2 Instance Type
variable "instance_type" {
  description = "EC2 Instance Type" # EC2 Instance Type
  type        = string              # String Variable

  validation {
    condition = contains(
      ["t3.micro", "t3.small"],
      var.instance_type
    )
    error_message = "Instance type must be t3.micro or t3.small."
  }
}

# Number of EC2 Instances
variable "instance_count" {
  description = "Number of EC2 Instances" # EC2 Instance Count
  type        = number                    # Number Variable
}

# Allowed SSH IP
variable "allowed_ssh_ip" {
  description = "Allowed SSH CIDR Block" # SSH Access CIDR
  type        = string                   # String Variable
}

# EC2 Key Pair
variable "key_name" {
  description = "EC2 Key Pair Name" # EC2 Key Pair
  type        = string              # String Variable
}