# Module: eks

The EKS cluster: control plane, a managed node group, and core add-ons (CoreDNS, kube-proxy, VPC
CNI, the Pod Identity agent, and the EBS CSI driver). Authentication uses the modern access-entry
API (no `aws-auth` ConfigMap). We use EKS Pod Identity, so no cluster OIDC provider is created.
Wraps `terraform-aws-modules/eks/aws` (v21).

The EBS CSI driver (needed for the Postgres PVC) gets its AWS permissions through a **Pod Identity
association** on `kube-system/ebs-csi-controller-sa` - the same modern mechanism the app uses.

## Inputs (all required - values come from the environment tfvars)
| Name | Type | Description |
|------|------|-------------|
| `cluster_name` | string | Cluster name. |
| `cluster_version` | string | Kubernetes version (verify with `aws eks describe-cluster-versions`). |
| `vpc_id` / `subnet_ids` | string / list | Where the cluster and nodes run (private subnets). |
| `endpoint_public_access` | bool | Expose the Kubernetes API on the internet. false = VPC-only; kubectl then needs a VPN, bastion or SSM tunnel. |
| `endpoint_private_access` | bool | Also resolve the API privately inside the VPC. |
| `public_access_cidrs` | list(string) | Who may reach the public endpoint. Ignored when public access is off. |
| `deletion_protection` | bool | Refuse `terraform destroy` on the cluster until turned off. On in prod. |
| `enabled_log_types` | list(string) | Control-plane log types (api, audit, authenticator, controllerManager, scheduler). `audit` is by far the highest volume. |
| `log_retention_days` | number | CloudWatch retention for the control-plane log group. |
| `node_ami_type` | string | e.g. `AL2023_x86_64_STANDARD`, or `AL2023_ARM_64_STANDARD` for Graviton. |
| `node_instance_types` / `node_capacity_type` | list / string | Node size and ON_DEMAND vs SPOT (validated). |
| `node_min` / `node_max` / `node_desired` | number | Node group sizing. |
| `node_volume_size` | number | Root EBS volume (GiB), gp3 and encrypted. |

## Outputs
| Name | Description |
|------|-------------|
| `cluster_name` | Cluster name. |
| `cluster_endpoint` | Kubernetes API endpoint. |
| `cluster_version` | Kubernetes version. |
