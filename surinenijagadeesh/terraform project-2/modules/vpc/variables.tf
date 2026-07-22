# Project Name
variable "project_name" {
  description = "Project Name"                 # Project Name
  type        = string                         # String Variable
}

# VPC CIDR Block
variable "vpc_cidr" {
  description = "CIDR Block for VPC"           # VPC Network Range
  type        = string                         # String Variable
}

# Public Subnets
variable "public_subnets" {
  description = "Public Subnet Configuration"  # Public Subnet Details

  type = map(object({
    cidr = string                              # CIDR Block
    az   = string                              # Availability Zone
  }))
}

# Private Subnets
variable "private_subnets" {
  description = "Private Subnet Configuration" # Private Subnet Details

  type = map(object({
    cidr = string                              # CIDR Block
    az   = string                              # Availability Zone
  }))
}

# Environment Name
variable "environment" {
  description = "Environment Name"             # dev or prod
  type        = string                         # String Variable
}