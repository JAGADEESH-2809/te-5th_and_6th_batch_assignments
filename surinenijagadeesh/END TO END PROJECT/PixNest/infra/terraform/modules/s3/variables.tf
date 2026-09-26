variable "name_prefix" {
  description = "Bucket name prefix; the account id is appended, so the name is stable across destroy/apply and distinct per environment."
  type        = string
}

variable "force_destroy" {
  description = "Allow deleting a non-empty (versioned) bucket. Dev only; false in production."
  type        = bool
}

variable "create_kms_key" {
  description = "Encrypt objects with a customer-managed KMS key (rotating, auditable) instead of free SSE-S3."
  type        = bool
}

variable "kms_key_rotation_days" {
  description = "Automatic KMS key rotation period in days. Ignored unless create_kms_key."
  type        = number
}

variable "kms_key_deletion_window_days" {
  description = "Waiting period before a scheduled KMS key deletion takes effect. Ignored unless create_kms_key."
  type        = number
}

variable "abort_incomplete_multipart_days" {
  description = "Days before an incomplete multipart upload is aborted and its parts are billed no more."
  type        = number
}

variable "noncurrent_version_expiration_days" {
  description = "Days a previous object version is kept before deletion."
  type        = number
}
