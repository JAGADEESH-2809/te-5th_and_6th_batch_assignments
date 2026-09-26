variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version."
  type        = string
}

variable "access_entries" {
  description = "IAM principals granted access to the Kubernetes API, keyed by a short name. Set namespaces to null for cluster-wide access, or to a list to scope the policy to those namespaces."
  type = map(object({
    principal_arn = string
    policy_arn    = string
    namespaces    = list(string)
  }))
}

variable "vpc_id" {
  description = "VPC to place the cluster in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the nodes (private subnets)."
  type        = list(string)
}

# --- API endpoint exposure ---
variable "endpoint_public_access" {
  description = "Expose the Kubernetes API on the internet (still filtered by public_access_cidrs). false = VPC-only, needs a VPN/bastion for kubectl."
  type        = bool
}

variable "endpoint_private_access" {
  description = "Also resolve the API privately inside the VPC."
  type        = bool
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Ignored when endpoint_public_access is false."
  type        = list(string)
}

# --- lifecycle ---
variable "deletion_protection" {
  description = "Block terraform destroy on the cluster until explicitly disabled. true in prod."
  type        = bool
}

# --- control-plane logging ---
variable "enabled_log_types" {
  description = "Control-plane log types to ship to CloudWatch (api, audit, authenticator, controllerManager, scheduler)."
  type        = list(string)
}

variable "log_retention_days" {
  description = "CloudWatch retention for the control-plane log group."
  type        = number
}

# --- node group ---
variable "node_ami_type" {
  description = "Managed node group AMI type (e.g. AL2023_x86_64_STANDARD, AL2023_ARM_64_STANDARD)."
  type        = string
}

variable "node_instance_types" {
  description = "Managed node group instance types."
  type        = list(string)
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_min" {
  description = "Minimum nodes."
  type        = number
}

variable "node_max" {
  description = "Maximum nodes."
  type        = number
}

variable "node_desired" {
  description = "Desired nodes."
  type        = number
}

variable "node_volume_size" {
  description = "Node root EBS volume size (GiB)."
  type        = number
}
