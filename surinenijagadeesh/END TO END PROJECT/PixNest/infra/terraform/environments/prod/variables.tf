# Every value comes from terraform.tfvars. No variable declares a default, so the tfvars file
# is the single, reviewable source of truth for what an environment looks like - nothing is
# hidden in a fallback that only shows up when you read this file.

# --- identity ---
variable "region" {
  description = "AWS region."
  type        = string
}

variable "project" {
  description = "Project name, used as the Project tag on every resource."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod); applied as the Environment tag on every resource."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for every named resource (ECR repos, IAM roles, VPC, photos bucket). MUST differ per environment when two environments share an AWS account, or they collide."
  type        = string
}

variable "github_repo" {
  description = "OIDC subject pattern for the repo (with @* wildcards for the immutable numeric ids)."
  type        = string
}

# --- networking ---
variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, one per AZ. EKS nodes and pods run here."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per AZ. Internet-facing load balancers live here."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "One NAT gateway for all AZs (cheap). false = one per AZ (HA)."
  type        = bool
}

variable "enable_flow_log" {
  description = "VPC flow logs to CloudWatch."
  type        = bool
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention for VPC flow logs. 0 = forever."
  type        = number
}

variable "enable_s3_endpoint" {
  description = "S3 gateway VPC endpoint (free; keeps S3 traffic off the NAT)."
  type        = bool
}

# --- EKS ---
variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version. Check currency with: aws eks describe-cluster-versions."
  type        = string
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API on the internet (filtered by public_access_cidrs)."
  type        = bool
}

variable "endpoint_private_access" {
  description = "Also resolve the Kubernetes API privately inside the VPC."
  type        = bool
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint."
  type        = list(string)
}

variable "cluster_deletion_protection" {
  description = "Block terraform destroy on the cluster until explicitly disabled."
  type        = bool
}

variable "cluster_enabled_log_types" {
  description = "Control-plane log types shipped to CloudWatch."
  type        = list(string)
}

variable "cluster_log_retention_days" {
  description = "CloudWatch retention for the control-plane log group."
  type        = number
}

variable "access_entries" {
  description = "IAM principals granted access to the Kubernetes API, keyed by a short name. namespaces = null means cluster-wide; a list scopes the policy to those namespaces. The pipeline role is granted separately by the module and is not listed here."
  type = map(object({
    principal_arn = string
    policy_arn    = string
    namespaces    = list(string)
  }))
}

variable "node_ami_type" {
  description = "Managed node group AMI type."
  type        = string
}

variable "node_instance_types" {
  description = "Managed node group instance types."
  type        = list(string)
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
}

variable "node_desired" {
  description = "Desired node count."
  type        = number
}

variable "node_min" {
  description = "Minimum node count."
  type        = number
}

variable "node_max" {
  description = "Maximum node count."
  type        = number
}

variable "node_volume_size" {
  description = "Node root EBS volume size (GiB)."
  type        = number
}

# --- registries ---
variable "ecr_untagged_expire_days" {
  description = "Days after which untagged ECR images are expired."
  type        = number
}

variable "ecr_force_delete" {
  description = "Let terraform destroy delete ECR repositories that still hold images. Dev only."
  type        = bool
}

# --- photos bucket ---
variable "s3_force_destroy" {
  description = "Allow deleting the non-empty (versioned) photos bucket on destroy. Dev only."
  type        = bool
}

variable "s3_create_kms_key" {
  description = "Encrypt photo objects with a customer-managed KMS key instead of free SSE-S3."
  type        = bool
}

variable "s3_kms_key_rotation_days" {
  description = "KMS key rotation period in days."
  type        = number
}

variable "s3_kms_key_deletion_window_days" {
  description = "Waiting period before a scheduled KMS key deletion takes effect."
  type        = number
}

variable "s3_abort_incomplete_multipart_days" {
  description = "Days before an incomplete multipart upload is aborted."
  type        = number
}

variable "s3_noncurrent_version_expiration_days" {
  description = "Days a previous object version is kept before deletion."
  type        = number
}

# --- backend pod -> S3 via EKS Pod Identity ---
variable "enable_alb_controller" {
  description = "Create the IAM role and Pod Identity association for the AWS Load Balancer Controller. The controller itself is installed by the platform layer."
  type        = bool
}

variable "alb_controller_namespace" {
  description = "Namespace the AWS Load Balancer Controller runs in."
  type        = string
}

variable "alb_controller_service_account" {
  description = "ServiceAccount the AWS Load Balancer Controller runs as."
  type        = string
}

variable "alb_controller_version" {
  description = "Controller release the vendored IAM policy was taken from. Keep in step with the chart version installed by the platform layer."
  type        = string
}

variable "enable_pod_identity" {
  description = "Create the backend role + EKS Pod Identity association."
  type        = bool
}

variable "k8s_namespace" {
  description = "Namespace the backend runs in."
  type        = string
}

variable "backend_service_account" {
  description = "Backend ServiceAccount name (must match the Helm chart serviceAccount.name)."
  type        = string
}
