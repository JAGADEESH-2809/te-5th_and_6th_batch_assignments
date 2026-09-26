variable "name_prefix" {
  description = "Name prefix for the role (e.g. pixnest -> pixnest-gha). Distinct per environment."
  type        = string
}

variable "github_repo" {
  description = "OIDC subject pattern for the repo. This account emits immutable-ID subjects (login@id/repo@id), so use wildcards like JAGADEESH-2809@*/pixnest@*."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs the CI role may push to."
  type        = list(string)
}


