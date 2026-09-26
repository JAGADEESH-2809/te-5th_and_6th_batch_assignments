# github-oidc module: an IAM role GitHub Actions (the app CI) assumes via OIDC to push images
# to ECR, with no static keys. The OIDC provider itself is created by the bootstrap and read here.

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "gha_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "gha" {
  name               = "${var.name_prefix}-gha"
  assume_role_policy = data.aws_iam_policy_document.gha_assume.json
}

# Push images to ECR. GetAuthorizationToken must be on "*" (it is not resource-scoped).
data "aws_iam_policy_document" "gha_ecr" {
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "gha_ecr" {
  name   = "${var.name_prefix}-gha-ecr"
  role   = aws_iam_role.gha.id
  policy = data.aws_iam_policy_document.gha_ecr.json
}
