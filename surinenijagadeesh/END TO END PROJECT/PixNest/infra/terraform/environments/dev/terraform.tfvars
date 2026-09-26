# dev: the demo environment. Cost-optimized; built and destroyed on demand through the
# terraform pipeline. Every variable is set here - variables.tf declares no defaults.

region      = "ap-south-1"
project     = "pixnest"
environment = "dev"

# Prefix for every named resource. dev keeps the bare project name, so the Helm values-eks.yaml
# overlays (pixnest-backend / pixnest-photos-<account>) stay valid.
name_prefix = "pixnest"

# GitHub OIDC subject pattern. This GitHub account emits immutable-id subjects
# (repo:login@id/name@id:...), so the @* wildcards are required.
github_repo = "JAGADEESH-2809@*/te-5th_and_6th_batch_assignments@*"

# --- networking ---
vpc_cidr                = "10.0.0.0/16"
private_subnet_cidrs    = ["10.0.0.0/20", "10.0.16.0/20"]    # one per AZ; nodes + pods
public_subnet_cidrs     = ["10.0.128.0/20", "10.0.144.0/20"] # one per AZ; internet-facing LBs
single_nat_gateway      = true                               # one NAT for both AZs (cheap)
enable_flow_log         = true
flow_log_retention_days = 7 # a demo environment does not need a long network audit trail
enable_s3_endpoint      = true

# --- EKS ---
cluster_name            = "pixnest"
cluster_version         = "1.36" # verify currency: aws eks describe-cluster-versions
endpoint_public_access  = true   # kubectl from anywhere - demo convenience
endpoint_private_access = false
public_access_cidrs     = ["0.0.0.0/0"] # open API endpoint - dev only
# The whole point of dev here is that `destroy` works unattended after a class.
cluster_deletion_protection = false
cluster_enabled_log_types   = ["api", "authenticator"] # audit logs are high volume and costly
cluster_log_retention_days  = 7

node_ami_type = "AL2023_x86_64_STANDARD"
# This AWS account may ONLY launch free-tier-eligible instance types: an apply with anything
# else fails at the node group with "InvalidParameterCombination - The specified instance type
# is not eligible for Free Tier". As of 2026-09-10 the eligible list in ap-south-1 is
# t3.micro, t3.small, t4g.micro, t4g.small, c7i-flex.large, m7i-flex.large. Check it with:
#   aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true #     --query 'InstanceTypes[].InstanceType'
# c7i-flex.large is the closest eligible match to the t3.medium this project was built on:
# same 2 vCPU and 4 GiB, and 29 pods per node instead of 17. The small types are not viable -
# t3.small caps at 11 pods, which the platform layer alone would fill.
node_instance_types = ["c7i-flex.large"]
node_capacity_type  = "ON_DEMAND"
node_desired        = 2
node_min            = 1
node_max            = 3
node_volume_size    = 30

# --- who may use kubectl on this cluster ---
# Declared here rather than granted by hand after the cluster exists, so cluster admin is
# visible in code review and is rebuilt with the environment. Every principal is listed,
# including the pipeline role: the module's enable_cluster_creator_admin_permissions is off
# because it grants to whoever runs terraform, which differs between the pipeline and a laptop.
# Policy list: aws eks list-access-policies.
# namespaces = null means cluster-wide; a list scopes the policy to those namespaces.
access_entries = {
  # The pipeline role. Terraform itself does not need cluster access - it only calls AWS APIs -
  # but having it makes the pipeline usable for debugging.
  pipeline = {
    principal_arn = "arn:aws:iam::258233813982:role/pixnest-tf"
    policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    namespaces    = null
  }
  siva = {
    principal_arn = "arn:aws:iam::258233813982:user/EKS-DEV"
    policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    namespaces    = null
  }
}

# --- registries ---
ecr_untagged_expire_days = 7
ecr_force_delete         = true # rebuilt constantly; let destroy clean up images too

# --- photos bucket ---
s3_force_destroy                      = true  # dev is torn down repeatedly
s3_create_kms_key                     = false # SSE-S3 is free and fine for demo data
s3_kms_key_rotation_days              = 365   # unused while create_kms_key is false
s3_kms_key_deletion_window_days       = 7     # unused while create_kms_key is false
s3_abort_incomplete_multipart_days    = 7
s3_noncurrent_version_expiration_days = 30

# --- AWS Load Balancer Controller ---
# Turns the app's Ingress into a real Application Load Balancer. Terraform creates only the IAM
# role and the Pod Identity association; the controller itself is installed by the platform layer,
# and the chart version there must match alb_controller_version so the vendored IAM policy in
# modules/alb-controller/iam_policy.json stays correct.
enable_alb_controller          = true
alb_controller_namespace       = "kube-system"
alb_controller_service_account = "aws-load-balancer-controller"
alb_controller_version         = "v3.5.0"

# --- backend pod -> S3 via EKS Pod Identity ---
enable_pod_identity     = true
k8s_namespace           = "pixnest"
backend_service_account = "pixnest-backend" # = Helm backend chart serviceAccount.name



