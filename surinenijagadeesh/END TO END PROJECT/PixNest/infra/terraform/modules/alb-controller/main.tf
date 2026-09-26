# alb-controller module: the IAM side of the AWS Load Balancer Controller.
#
# The controller runs IN the cluster and calls the AWS APIs to create and manage Application
# Load Balancers from Ingress objects. It therefore needs real AWS permissions, granted the same
# way the app gets them: EKS Pod Identity, not IRSA and not node credentials.
#
# This module creates the role and the association only. Installing the controller itself is the
# platform layer's job (helm), exactly like ingress-nginx was - Terraform owns cloud resources,
# not cluster software.

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name_prefix}-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  description        = "AWS Load Balancer Controller for the ${var.cluster_name} cluster"
}

# The permission set is published by the controller project and changes between releases, so it
# is vendored here at a pinned version rather than hand-written or fetched at apply time. Update
# it deliberately when bumping the controller:
#   curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/\
#     aws-load-balancer-controller/<tag>/docs/install/iam_policy.json
resource "aws_iam_policy" "this" {
  name        = "${var.name_prefix}-alb-controller"
  description = "Published policy for AWS Load Balancer Controller ${var.controller_version}"
  policy      = file("${path.module}/iam_policy.json")
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}

# Binds (namespace + ServiceAccount) to the role. The Helm chart creates a ServiceAccount with
# this name and needs NO eks.amazonaws.com/role-arn annotation, because Pod Identity resolves
# the mapping here rather than from the ServiceAccount.
resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.this.arn
}
