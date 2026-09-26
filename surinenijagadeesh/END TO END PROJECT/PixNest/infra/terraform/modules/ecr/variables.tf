variable "repositories" {
  description = "ECR repository names to create."
  type        = list(string)
}

variable "untagged_expire_days" {
  description = "Days after which untagged images are expired."
  type        = number
}

variable "force_delete" {
  description = "Let terraform destroy delete a repository that still contains images. Dev only."
  type        = bool
}
