# Module: vpc

A 2-AZ VPC for the EKS cluster: public + private subnets, an Internet Gateway, NAT (one shared or
one per AZ), VPC flow logs, a locked-down default security group, and a free S3 gateway endpoint.
Subnets are tagged for EKS load-balancer discovery. Wraps `terraform-aws-modules/vpc/aws` (v6).

## Inputs (all required - values come from the environment tfvars)
| Name | Type | Description |
|------|------|-------------|
| `name_prefix` | string | Name prefix (`<name_prefix>-vpc`). Distinct per environment. |
| `cidr` | string | VPC CIDR. |
| `private_subnet_cidrs` | list(string) | Private subnet CIDRs, one per AZ (EKS nodes/pods). Validated: >= 2. |
| `public_subnet_cidrs` | list(string) | Public subnet CIDRs, one per AZ (internet-facing LBs). Validated: same length as private. |
| `single_nat_gateway` | bool | One NAT (dev) vs per-AZ (prod). |
| `enable_flow_log` | bool | VPC flow logs to CloudWatch. |
| `flow_log_retention_days` | number | Retention for those logs. 0 = keep forever, which bills forever. |
| `enable_s3_endpoint` | bool | S3 gateway endpoint (private, free). |

The AZ count is derived from the number of subnet CIDRs, and AZs are chosen in order from those
available in the region.

## Outputs
| Name | Description |
|------|-------------|
| `vpc_id` | The VPC id. |
| `private_subnet_ids` | Private subnets (EKS nodes/pods). |
| `public_subnet_ids` | Public subnets (internet-facing load balancers). |
