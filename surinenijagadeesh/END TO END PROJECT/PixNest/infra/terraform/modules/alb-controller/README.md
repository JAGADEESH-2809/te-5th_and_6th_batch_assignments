# Module: alb-controller

The IAM half of the **AWS Load Balancer Controller**. The controller runs inside the cluster and
turns `Ingress` objects into real **Application Load Balancers**, so it needs AWS permissions.
Those come from **EKS Pod Identity**, the same mechanism the app uses for S3 - no IRSA, no static
keys, no ServiceAccount annotation.

This module deliberately does **not** install the controller. Terraform owns cloud resources; the
controller itself is cluster software and belongs to the platform layer
([PLATFORM-INSTALL.md](../../../../docs/PLATFORM-INSTALL.md) step 3, or `bootstrap-cluster.sh`).

## What it creates
- an IAM role trusted by `pods.eks.amazonaws.com`
- an IAM policy from the vendored `iam_policy.json`
- a Pod Identity association mapping (namespace + ServiceAccount) to the role

## The vendored policy
`iam_policy.json` is the file published by the controller project, pinned to a release. It grants
across `elasticloadbalancing`, `ec2`, `acm`, `wafv2`, `waf-regional`, `shield`, `cognito-idp` and
`iam` (for the service-linked role). It is vendored rather than fetched at apply time so a plan is
reproducible and the diff is reviewable.

To bump the controller, update both the chart version in the platform layer and this file:

```bash
curl -o iam_policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/<tag>/docs/install/iam_policy.json
```

## Subnet discovery
The controller finds subnets by tag, which the `vpc` module already applies:
`kubernetes.io/role/elb = 1` on public subnets (internet-facing) and
`kubernetes.io/role/internal-elb = 1` on private ones. Without those tags an Ingress stays
pending with "unable to discover subnets".

## The full prerequisite chain
This module is only one link. The complete picture - the request path, all six prerequisites
with their failure modes, debugging, teardown order and the TLS upgrade - is in
[INGRESS-AND-ALB.md](../../../../docs/INGRESS-AND-ALB.md). The two that are easiest to
miss are the `eks-pod-identity-agent` add-on (without it nothing delivers a token to the pod) and
the app NetworkPolicy, which must admit the **VPC CIDR** rather than an ingress namespace,
because an ALB with `target-type: ip` reaches pods from the VPC and not from inside the cluster.

## Inputs (all required - values come from the environment tfvars)
| Name | Type | Description |
|------|------|-------------|
| `name_prefix` | string | Role/policy prefix. |
| `cluster_name` | string | Cluster the association binds to. |
| `namespace` | string | Namespace the controller runs in. |
| `service_account` | string | ServiceAccount name the chart creates. |
| `controller_version` | string | Version the vendored policy came from. |

## Outputs
| Name | Description |
|------|-------------|
| `role_arn` | The controller's role ARN. |
| `role_name` | The role name. |
