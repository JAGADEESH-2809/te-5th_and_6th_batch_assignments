variable "name_prefix" {
  description = "Name prefix for the role and policy (e.g. pixnest -> pixnest-alb-controller)."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster the controller manages load balancers for."
  type        = string
}

variable "namespace" {
  description = "Namespace the controller runs in (the Helm chart defaults to kube-system)."
  type        = string
}

variable "service_account" {
  description = "ServiceAccount the controller runs as (the Helm chart defaults to aws-load-balancer-controller)."
  type        = string
}

variable "controller_version" {
  description = "Controller version the vendored iam_policy.json was taken from. Recorded on the policy description so a drifting policy is obvious."
  type        = string
}

