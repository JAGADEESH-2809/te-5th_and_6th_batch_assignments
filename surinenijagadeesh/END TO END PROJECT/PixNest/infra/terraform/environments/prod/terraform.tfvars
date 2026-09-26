# prod: HA, hardened, and hard to delete by accident. Every variable is set here - variables.tf
# declares no defaults.
#
# In a real organisation prod would live in its own AWS account. It does not here, so every
# named resource carries the "pixnest-prod" prefix: IAM role names are account-global, and
# ECR repository and S3 bucket names are unique per account, so a shared prefix would make
# `terraform apply` fail with EntityAlreadyExists / RepositoryAlreadyExists.

region      = "ap-south-1"
project     = "pixnest"
environment = "prod"

name_prefix = "pixnest-prod"

github_repo = "JAGADEESH-2809@*/te-5th_and_6th_batch_assignments@*"

# --- networking (its own CIDR range, so dev and prod could be peered later) ---
vpc_cidr                = "10.1.0.0/16"
private_subnet_cidrs    = ["10.1.0.0/20", "10.1.16.0/20"]
public_subnet_cidrs     = ["10.1.128.0/20", "10.1.144.0/20"]
single_nat_gateway      = false # one NAT per AZ: no single point of failure
enable_flow_log         = true
flow_log_retention_days = 90 # network audit trail worth keeping
enable_s3_endpoint      = true

# --- EKS ---
cluster_name    = "pixnest-prod"
cluster_version = "1.36"

# The API endpoint stays public but is reachable only from the listed CIDRs, and also resolves
# privately inside the VPC. Set endpoint_public_access = false for a fully private control plane;
# kubectl and the bootstrap script then need a VPN, a bastion or an SSM tunnel.
endpoint_public_access  = true
endpoint_private_access = true
# Set 2026-09-10 to the operator's public address. This is almost certainly a dynamic
# residential IP: when it changes, kubectl and bootstrap-cluster.sh stop reaching the API and
# the fix is to edit this line and apply. A static office or VPN range is the durable answer.
#   curl -s https://checkip.amazonaws.com
public_access_cidrs = ["49.43.229.224/32"]

# Refuses `terraform destroy` on the cluster. Flip to false, apply, then destroy - deliberately
# a two-step operation in production.
cluster_deletion_protection = true
cluster_enabled_log_types   = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
cluster_log_retention_days  = 90

# Node sizing is deliberately MINIMAL while prod carries no workload. t3.medium is the floor,
# not a preference: pod density is capped by ENIs, and t3.small tops out around 11 pods, which
# the platform layer alone (aws-node, kube-proxy, CoreDNS, EBS CSI, ingress-nginx, Argo CD)
# would fill before a single application pod scheduled. Two nodes across two AZs still survives
# losing one, so the HA story below the node layer stays intact.
#
# When real traffic arrives, restore: ["m5.large"], desired/min 3, max 6, 50 GiB.
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
node_capacity_type  = "ON_DEMAND" # SPOT would trade cost for eviction risk
node_desired        = 2
node_min            = 2
node_max            = 4
node_volume_size    = 30

# --- who may use kubectl on this cluster ---
# Production grants to a ROLE, never to a person: access is then revoked by changing the role's
# trust policy rather than by editing the cluster, and there is one entry however many people
# are on the team. Create the role before applying, or the entry fails with an invalid principal.
# The pipeline role is granted separately by the module.
access_entries = {
  pipeline = {
    principal_arn = "arn:aws:iam::258233813982:role/pixnest-tf"
    policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    namespaces    = null
  }
  # platform_admin = {
  #   principal_arn = "arn:aws:iam::258233813982:role/pixnest-prod-admin"
  #   policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  #   namespaces    = null
  # }
  # deployer = {
  #   principal_arn = "arn:aws:iam::258233813982:role/pixnest-prod-deployer"
  #   policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
  #   namespaces    = ["pixnest"]
  # }
}

# --- registries ---
ecr_untagged_expire_days = 14
ecr_force_delete         = false # never let destroy throw away deployable artifacts

# --- photos bucket ---
s3_force_destroy                      = false # destroy must never delete production photos
s3_create_kms_key                     = true  # customer-managed, rotating, auditable key
s3_kms_key_rotation_days              = 365
s3_kms_key_deletion_window_days       = 30 # maximum thinking time before a key is gone for good
s3_abort_incomplete_multipart_days    = 7
s3_noncurrent_version_expiration_days = 365

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
backend_service_account = "pixnest-backend"



