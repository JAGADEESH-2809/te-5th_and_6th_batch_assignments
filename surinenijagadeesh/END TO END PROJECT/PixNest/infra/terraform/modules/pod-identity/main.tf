# pod-identity module: EKS Pod Identity for the backend pod -> S3 (the modern successor to IRSA).
# The role trusts the EKS service principal; an association maps (namespace + ServiceAccount) to
# the role; the agent add-on runs on the cluster. Instantiate this module only when a cluster exists.

data "aws_region" "current" {}

data "aws_iam_policy_document" "backend_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backend" {
  name               = "${var.name_prefix}-backend"
  assume_role_policy = data.aws_iam_policy_document.backend_assume.json
}

# Least-privilege: only the objects in this one bucket.
data "aws_iam_policy_document" "backend_s3" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = ["${var.bucket_arn}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.bucket_arn]
  }

  # When the bucket is encrypted with a customer-managed KMS key, S3 permissions alone are not
  # enough: every upload needs a data key and every download needs a decrypt. Scoped to that one
  # key, and only when S3 is the caller.
  dynamic "statement" {
    for_each = var.bucket_kms_key_arn == null ? [] : [var.bucket_kms_key_arn]
    content {
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [statement.value]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${data.aws_region.current.region}.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy" "backend_s3" {
  name   = "${var.name_prefix}-backend-s3"
  role   = aws_iam_role.backend.id
  policy = data.aws_iam_policy_document.backend_s3.json
}

# The eks-pod-identity-agent add-on is installed by the eks module's addons.

resource "aws_eks_pod_identity_association" "backend" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.backend.arn
}
