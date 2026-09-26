# prod environment: compose the shared modules. Every input is passed explicitly from the
# variables in terraform.tfvars - neither the root nor the local modules declare defaults. Copy
# this directory to add another environment: change backend.tf's key and terraform.tfvars.
#
# name_prefix is what keeps environments from colliding: ECR repositories, IAM roles and the
# photos bucket are all named from it, and IAM role names are account-global.

module "ecr" {
  source               = "../../modules/ecr"
  repositories         = ["${var.name_prefix}-backend", "${var.name_prefix}-frontend"]
  untagged_expire_days = var.ecr_untagged_expire_days
  force_delete         = var.ecr_force_delete
}

module "s3" {
  source                             = "../../modules/s3"
  name_prefix                        = "${var.name_prefix}-photos"
  force_destroy                      = var.s3_force_destroy
  create_kms_key                     = var.s3_create_kms_key
  kms_key_rotation_days              = var.s3_kms_key_rotation_days
  kms_key_deletion_window_days       = var.s3_kms_key_deletion_window_days
  abort_incomplete_multipart_days    = var.s3_abort_incomplete_multipart_days
  noncurrent_version_expiration_days = var.s3_noncurrent_version_expiration_days
}

module "github_oidc" {
  source              = "../../modules/github-oidc"
  name_prefix         = var.name_prefix
  github_repo         = var.github_repo
  ecr_repository_arns = module.ecr.repository_arns
}

# Networking + the EKS cluster. Sizing/HA/exposure differ per environment via terraform.tfvars.
module "vpc" {
  source                  = "../../modules/vpc"
  name_prefix             = var.name_prefix
  cidr                    = var.vpc_cidr
  private_subnet_cidrs    = var.private_subnet_cidrs
  public_subnet_cidrs     = var.public_subnet_cidrs
  single_nat_gateway      = var.single_nat_gateway
  enable_flow_log         = var.enable_flow_log
  flow_log_retention_days = var.flow_log_retention_days
  enable_s3_endpoint      = var.enable_s3_endpoint
}

module "eks" {
  source                  = "../../modules/eks"
  cluster_name            = var.cluster_name
  cluster_version         = var.cluster_version
  vpc_id                  = module.vpc.vpc_id
  subnet_ids              = module.vpc.private_subnet_ids
  endpoint_public_access  = var.endpoint_public_access
  endpoint_private_access = var.endpoint_private_access
  public_access_cidrs     = var.public_access_cidrs
  access_entries          = var.access_entries
  deletion_protection     = var.cluster_deletion_protection
  enabled_log_types       = var.cluster_enabled_log_types
  log_retention_days      = var.cluster_log_retention_days
  node_ami_type           = var.node_ami_type
  node_instance_types     = var.node_instance_types
  node_capacity_type      = var.node_capacity_type
  node_desired            = var.node_desired
  node_min                = var.node_min
  node_max                = var.node_max
  node_volume_size        = var.node_volume_size
}

# AWS Load Balancer Controller -> ELB/ACM APIs via EKS Pod Identity. The controller turns the
# app's Ingress into a real Application Load Balancer; this is only its IAM half.
module "alb_controller" {
  source             = "../../modules/alb-controller"
  count              = var.enable_alb_controller ? 1 : 0
  name_prefix        = var.name_prefix
  cluster_name       = module.eks.cluster_name
  namespace          = var.alb_controller_namespace
  service_account    = var.alb_controller_service_account
  controller_version = var.alb_controller_version
}

# Backend pod -> S3 via EKS Pod Identity (bound to the cluster the eks module creates).
module "pod_identity" {
  source             = "../../modules/pod-identity"
  count              = var.enable_pod_identity ? 1 : 0
  name_prefix        = var.name_prefix
  cluster_name       = module.eks.cluster_name
  namespace          = var.k8s_namespace
  service_account    = var.backend_service_account
  bucket_arn         = module.s3.bucket_arn
  bucket_kms_key_arn = module.s3.kms_key_arn
}
