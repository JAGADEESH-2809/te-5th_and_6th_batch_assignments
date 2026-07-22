# -----------------------------
# VPC ID
# -----------------------------
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

# -----------------------------
# Public Subnet ID
# -----------------------------
variable "subnet_id" {
  description = "Public Subnet ID"
  type        = string
}

# -----------------------------
# Environment Name
# -----------------------------
variable "environment" {
  description = "Environment Name"
  type        = string
}

# -----------------------------
# EC2 Instance Type
# -----------------------------
variable "instance_type" {

  description = "EC2 Instance Type"
  type        = string

  validation {
    condition = contains(
      ["t2.micro", "t3.micro", "t3.small"],
      var.instance_type
    )

    error_message = "Instance type must be t2.micro, t3.micro or t3.small."
  }

}

# -----------------------------
# Number of EC2 Instances
# -----------------------------
variable "instance_count" {
  description = "Number of EC2 Instances"
  type        = number
}

# -----------------------------
# SSH Allowed IP
# -----------------------------
variable "allowed_ssh_ip" {
  description = "IP allowed to SSH into EC2"
  type        = string
}

# -----------------------------
# Key Pair Name
# -----------------------------
variable "key_name" {
  description = "EC2 Key Pair Name"
  type        = string
}
# -----------------------------
# Project Name
# -----------------------------
variable "project_name" {
  description = "Project Name"
  type        = string
}