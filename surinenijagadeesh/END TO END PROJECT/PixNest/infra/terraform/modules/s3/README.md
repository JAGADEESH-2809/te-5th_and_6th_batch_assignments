# Module: s3

The private, versioned bucket that stores uploaded photos. Public access is fully blocked, ACLs
are disabled, and a bucket policy rejects any non-TLS request; images are served to the browser
with short-lived presigned URLs.

The bucket name is `<name_prefix>-<account id>`. Deriving it from the account rather than a random
suffix means destroying and re-applying an environment reproduces the **same** name, so the Helm
values stay valid across teardowns.

## Encryption
`create_kms_key = false` uses SSE-S3 (AES256): free, managed entirely by AWS, adequate for a
throwaway environment. `true` creates a customer-managed KMS key with automatic rotation and its
own access policy, and enables S3 Bucket Keys, which cut KMS request charges by roughly 99%. When
a key is used, the backend role needs `kms:Decrypt` and `kms:GenerateDataKey` on it - the
`pod-identity` module adds that automatically from the `kms_key_arn` output.

## Inputs (all required - values come from the environment tfvars)
| Name | Type | Description |
|------|------|-------------|
| `name_prefix` | string | Bucket name prefix; the account id is appended. |
| `force_destroy` | bool | Let destroy delete a non-empty versioned bucket. Dev only. |
| `create_kms_key` | bool | Customer-managed KMS key instead of SSE-S3. |
| `kms_key_rotation_days` | number | Rotation period. Ignored unless `create_kms_key`. |
| `kms_key_deletion_window_days` | number | Waiting period before a scheduled key deletion completes. |
| `abort_incomplete_multipart_days` | number | When to abort and stop billing failed multipart uploads. |
| `noncurrent_version_expiration_days` | number | How long a previous object version is kept. |

## Outputs
| Name | Description |
|------|-------------|
| `bucket` | Bucket name (Helm `backend.env.S3_BUCKET`). |
| `bucket_arn` | Bucket ARN (scopes the backend's least-privilege S3 policy). |
| `kms_key_arn` | The encryption key ARN, or null when the bucket uses SSE-S3. |
