# Module: pod-identity

EKS Pod Identity for the backend pod to call S3 with no static keys - the modern successor to
IRSA. The IAM role trusts the EKS service principal (`pods.eks.amazonaws.com`); a Pod Identity
association maps (namespace + ServiceAccount) to the role; and the `eks-pod-identity-agent`
add-on runs on the cluster. Instantiate this module only when an EKS cluster exists (each
environment gates it behind `enable_pod_identity`).

## Inputs
| Name | Type | Description |
|------|------|-------------|
| `name_prefix` | string | Name prefix (e.g. `pixnest` -> role `pixnest-backend`). Distinct per environment. |
| `cluster_name` | string | EKS cluster for the association + add-on. |
| `namespace` | string | Namespace of the backend ServiceAccount. |
| `service_account` | string | Backend ServiceAccount name. |
| `bucket_arn` | string | Photos bucket ARN (scopes the S3 policy). |
| `bucket_kms_key_arn` | string | KMS key encrypting the bucket, or `null` for SSE-S3. When set, the role also gets `kms:Decrypt` / `kms:GenerateDataKey` on that key, conditioned on S3 being the caller - without it every upload and download fails with AccessDenied. |

## Outputs
| Name | Description |
|------|-------------|
| `role_arn` | The backend role ARN (bound to the SA via Pod Identity). |

