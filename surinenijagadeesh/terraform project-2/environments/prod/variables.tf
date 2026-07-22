# AWS Region
variable "aws_region" {

  description = "AWS Region"                          # AWS deployment region
  type        = string                               # String value

}

# Environment Name
variable "environment" {

  description = "Environment Name"                   # dev or prod
  type        = string                               # String value

}

# VPC CIDR Block
variable "vpc_cidr" {

  description = "VPC CIDR Block"                     # VPC CIDR
  type        = string                               # String value

}

# Public Subnets
variable "public_subnets" {

  description = "Public Subnet Details"              # Public subnet details

  type = map(object({
    cidr = string                                    # Subnet CIDR
    az   = string                                    # Availability Zone
  }))

}

# Private Subnets
variable "private_subnets" {

  description = "Private Subnet Details"             # Private subnet details

  type = map(object({
    cidr = string                                    # Subnet CIDR
    az   = string                                    # Availability Zone
  }))

}

# EC2 Instance Type
variable "instance_type" {

  description = "EC2 Instance Type"                  # EC2 instance type
  type        = string                               # String value

  validation {
    condition     = contains(["t3.micro", "t3.small"], var.instance_type) # Allowed types
    error_message = "Use only t3.micro or t3.small."                       # Error message
  }

}

# Number of EC2 Instances
variable "instance_count" {

  description = "Number of EC2 Instances"            # Total EC2 instances
  type        = number                               # Numeric value

}

# SSH Allowed IP
variable "allowed_ssh_ip" {

  description = "Allowed SSH IP"                     # Your public IP with /32
  type        = string                               # String value

}
# Project Name
variable "project_name" {

  description = "Project Name"                        # Project Name
  type        = string                                # String Value

}

# EC2 Key Pair
variable "key_name" {

  description = "EC2 Key Pair Name"                   # EC2 Key Pair
  type        = string                                # String Value

}