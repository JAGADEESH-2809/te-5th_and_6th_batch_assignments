variable "name_prefix" {
  description = "Name prefix for the role (e.g. pixnest -> pixnest-backend). Distinct per environment."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name for the Pod Identity association."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the backend ServiceAccount."
  type        = string
}

variable "service_account" {
  description = "Backend ServiceAccount name to bind to the role."
  type        = string
}

variable "bucket_arn" {
  description = "ARN of the photos bucket the backend may read/write."
  type        = string
}

variable "bucket_kms_key_arn" {
  description = "KMS key encrypting the bucket, or null for SSE-S3. When set, the role also gets kms:Decrypt/GenerateDataKey on that key via S3."
  type        = string
}

