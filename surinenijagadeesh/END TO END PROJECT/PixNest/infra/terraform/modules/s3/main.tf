# S3 module: a private, encrypted, versioned bucket for the uploaded photos. Public access is
# fully blocked and ACLs are disabled; images are served with short-lived presigned URLs.
#
# The name is derived from the AWS account id rather than a random suffix, so destroying and
# re-applying the environment always produces the SAME bucket name. That keeps the Helm values
# valid across teardowns (a random suffix would silently break them on every recreate). The
# prefix carries the environment, so two environments can coexist in one account.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "photos" {
  bucket = "${var.name_prefix}-${data.aws_caller_identity.current.account_id}"
  # Versioning keeps old object versions, which blocks terraform destroy. Dev environments are
  # torn down repeatedly, so allow it there; production keeps this false.
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "photos" {
  bucket                  = aws_s3_bucket.photos.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "photos" {
  bucket = aws_s3_bucket.photos.id
  rule {
    object_ownership = "BucketOwnerEnforced" # disables ACLs; ownership is by the bucket owner
  }
}

# ----------------------------------------------------------------------------
# Encryption. SSE-S3 (AES256) is free and adequate for a throwaway environment. A customer-
# managed KMS key adds an auditable, rotatable key with its own access policy, which is what a
# production data store wants - at the cost of a monthly key charge and KMS request charges.
# Bucket Keys cut those request charges by roughly 99% and are only meaningful with KMS.
# ----------------------------------------------------------------------------
resource "aws_kms_key" "photos" {
  count                   = var.create_kms_key ? 1 : 0
  description             = "${var.name_prefix} photo objects at rest"
  enable_key_rotation     = true
  rotation_period_in_days = var.kms_key_rotation_days
  deletion_window_in_days = var.kms_key_deletion_window_days
}

resource "aws_kms_alias" "photos" {
  count         = var.create_kms_key ? 1 : 0
  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.photos[0].key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "photos" {
  bucket = aws_s3_bucket.photos.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.create_kms_key ? "aws:kms" : "AES256"
      kms_master_key_id = var.create_kms_key ? aws_kms_key.photos[0].arn : null
    }
    bucket_key_enabled = var.create_kms_key
  }
}

resource "aws_s3_bucket_versioning" "photos" {
  bucket = aws_s3_bucket.photos.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "photos" {
  bucket = aws_s3_bucket.photos.id
  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"
    # Empty filter = applies to every object. Required: the provider now expects exactly one of
    # filter/prefix per rule, and omitting both becomes an error in a future provider version.
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_days
    }
  }
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }
}

# Reject any non-TLS access to the bucket.
data "aws_iam_policy_document" "tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.photos.arn, "${aws_s3_bucket.photos.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "photos" {
  bucket = aws_s3_bucket.photos.id
  policy = data.aws_iam_policy_document.tls_only.json
}
