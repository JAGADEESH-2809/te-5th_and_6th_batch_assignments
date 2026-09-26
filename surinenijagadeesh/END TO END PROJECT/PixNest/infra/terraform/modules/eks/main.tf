# EKS module: the cluster (public API), a managed node group, and core add-ons. Auth uses the
# modern EKS access-entry API (no aws-auth ConfigMap). We use EKS Pod Identity, not IRSA, so the
# module does not create a cluster OIDC provider. Wraps the community EKS module.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.25" # verify currency: registry.terraform.io/modules/terraform-aws-modules/eks/aws

  # v21 dropped the cluster_ prefix from most inputs (cluster_name -> name, etc.).
  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  # Endpoint exposure is per-environment. Turning public access off entirely means the API is
  # reachable only from inside the VPC, so kubectl then needs a VPN, bastion or SSM tunnel.
  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.public_access_cidrs
  endpoint_private_access      = var.endpoint_private_access
  # Deliberately OFF. When true the module grants cluster-admin to whatever identity happens to
  # run terraform - pixnest-tf from the pipeline, but a human's own ARN from a laptop. The
  # config then plans differently depending on who runs it, and a local plan proposes destroying
  # and recreating the entry. Access is declared in access_entries below instead, so the plan is
  # the same everywhere and who holds cluster-admin is visible in code review.
  enable_cluster_creator_admin_permissions = false
  authentication_mode                      = "API"
  enable_irsa                              = false # we use EKS Pod Identity

  # Refuses `terraform destroy` on the cluster until it is turned off. On in prod.
  deletion_protection = var.deletion_protection

  # Encrypt Kubernetes secrets at rest with a dedicated KMS key.
  create_kms_key = true
  encryption_config = {
    resources = ["secrets"]
  }

  # Control-plane logs to CloudWatch (audit trail). Which types, and for how long, is a
  # per-environment cost/compliance decision - audit logs in particular are high volume.
  enabled_log_types                      = var.enabled_log_types
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Who may talk to the Kubernetes API, declared rather than granted by hand afterwards.
  # The cluster creator (the pipeline role) is added separately by
  # enable_cluster_creator_admin_permissions above; everyone else comes from here.
  access_entries = {
    for name, e in var.access_entries : name => {
      principal_arn = e.principal_arn
      policy_associations = {
        this = {
          policy_arn = e.policy_arn
          # Both branches of a conditional must have the SAME attributes or Terraform rejects it
          # with "Inconsistent conditional result types", so the scope is built as one object and
          # namespaces stays null for cluster-wide access.
          access_scope = {
            type       = e.namespaces == null ? "cluster" : "namespace"
            namespaces = e.namespaces
          }
        }
      }
    }
  }

  # v21 installs the most recent add-on version by default (most_recent = true).
  #
  # ORDER MATTERS. before_compute = true installs an add-on before the node group is created.
  # The CNI and kube-proxy have to be there first: without them a node never reaches Ready, so
  # the node group fails with "NodeCreationFailure: Unhealthy nodes in the kubernetes cluster",
  # while the add-ons that would have fixed it sit queued behind that same node group. v21
  # hardcodes bootstrap_self_managed_addons = false, so nothing else installs them for you -
  # this is the trap when moving from v20, where EKS still seeded them itself.
  addons = {
    vpc-cni                = { before_compute = true }
    kube-proxy             = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true } # required for Pod Identity to work

    # These schedule as normal workloads, so they need Ready nodes and must come after compute.
    coredns            = {}
    aws-ebs-csi-driver = {} # permissions come from the Pod Identity association below
  }

  eks_managed_node_groups = {
    default = {
      # AL2023 explicitly: AL2 AMIs do not exist for Kubernetes 1.33+. Variable so an
      # environment can move to Graviton (AL2023_ARM_64_STANDARD) or GPU images.
      ami_type       = var.node_ami_type
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type
      min_size       = var.node_min
      max_size       = var.node_max
      desired_size   = var.node_desired
      labels         = { role = "general" }

      # Security hardening: IMDSv2 required, and pods cannot reach node credentials.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      # Encrypted gp3 root volume.
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.node_volume_size
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
    }
  }
}

# ----------------------------------------------------------------------------
# EBS CSI driver needs AWS permissions to create/attach volumes. Grant them with Pod Identity
# (the same modern mechanism the app uses), not IRSA.
# ----------------------------------------------------------------------------
data "aws_iam_policy_document" "ebs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.ebs_assume.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
}

