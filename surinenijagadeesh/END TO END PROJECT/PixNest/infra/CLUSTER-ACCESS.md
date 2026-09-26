# Cluster access: from a fresh EKS cluster to a working kubectl

Terraform creates the cluster, but creating a cluster does **not** give you access to it. This is
the step that surprises people: `terraform apply` finishes, the console shows the cluster as
Active, and `kubectl get nodes` answers `Unauthorized`. That is correct behaviour, not a bug.

This document covers what to install, how EKS decides who may do what, and the exact commands to
grant, verify and revoke access. Every command here was run against the live `pixnest` cluster.

- Deploying the app on top of this: [EKS-DEPLOY.md](EKS-DEPLOY.md)
- Installing the platform layer by hand: [../docs/PLATFORM-INSTALL.md](../docs/PLATFORM-INSTALL.md)

---

## 1. Install the tools

Four tools, in the order you need them.

| Tool | What it is for | Version used here |
|------|----------------|-------------------|
| AWS CLI v2 | authentication, `update-kubeconfig`, access entries | 2.33.28 |
| kubectl | talking to the Kubernetes API | v1.34.1 |
| helm | installing the AWS Load Balancer Controller and the app charts | v3.20.0 |
| git | the GitOps source of truth | any recent |

**kubectl version skew.** Kubernetes supports a client one minor version either side of the
server. The cluster runs 1.36, so a 1.34 client works, and so would 1.35 or 1.37. A client many
versions behind will fail in confusing ways on newer resource types.

```bash
# macOS
brew install awscli kubernetes-cli helm

# Windows
winget install Amazon.AWSCLI Kubernetes.kubectl Helm.Helm

# Linux (kubectl; see the Helm and AWS docs for those)
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl
```

Check all three answer:

```bash
aws --version
kubectl version --client
helm version --short
```

## 2. Point the AWS CLI at the right account

Everything below authenticates as whoever the AWS CLI currently is. Set the profile explicitly
and clear any stale environment credentials, or the CLI silently uses the wrong identity and
fails with `InvalidClientTokenId`:

```bash
export AWS_PROFILE=pixnest-boot
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
aws sts get-caller-identity
```

Note the `Arn` it prints. That string is your identity to EKS, and you will need it in sections 4 and 5:

```json
{ "Account": "359367063384", "Arn": "arn:aws:iam::359367063384:user/Siva" }
```

## 3. Understand what you are about to configure

EKS access has **two halves**, and both must be satisfied.

1. **Authentication - who are you?** Answered by AWS IAM. kubectl calls the AWS CLI behind the
   scenes to sign a token proving your IAM identity.
2. **Authorization - what may you do?** Answered by Kubernetes RBAC. IAM has no opinion here;
   `AdministratorAccess` on the AWS side grants exactly nothing inside the cluster.

An **access entry** is the bridge: it maps one IAM principal to a Kubernetes identity. An
**access policy** attached to that entry says what the identity may do.

This cluster uses `authentication_mode = "API"`, so access entries are the only mechanism. The
older `aws-auth` ConfigMap does not apply. That is a deliberate choice: the ConfigMap was a single
YAML blob in `kube-system` that you had to edit live, with no audit trail and a real chance of
locking everyone out with one bad edit. Access entries are ordinary AWS API calls, so they are
logged in CloudTrail and cannot be corrupted by a typo in a text editor.

### Who already has access on a fresh cluster

Four entries exist before you add anything, and each has a distinct reason:

| Principal | Type | Created by |
|-----------|------|------------|
| `pixnest-tf`, and anyone else listed in `access_entries` | STANDARD | **Terraform**, from the environment's `terraform.tfvars`. See section 4. |
| `default-eks-node-group-*` | EC2_LINUX | EKS itself, when the managed node group is created. This is how the **nodes** authenticate. Never touch it. |
| `AWSServiceRoleForAmazonEKS` | STANDARD | AWS, for Pod Identity, cluster insights and events. |

The important consequence if you are **not** in `access_entries`: **the human who ran Terraform
through a pipeline has no access**, because the pipeline role holds it, not the person. Section 5
is the imperative way to fix that for yourself; section 4 is the way to fix it for good.

List them yourself:

```bash
aws eks list-access-entries --cluster-name pixnest --region ap-south-1
```

## 4. The declarative way: put it in Terraform

This is the preferred route, and what this project does. Each environment's `terraform.tfvars`
holds an `access_entries` map, and Terraform creates both the entry and its policy association:

```hcl
access_entries = {
  pipeline = {
    principal_arn = "arn:aws:iam::359367063384:role/pixnest-tf"
    policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    namespaces    = null # null = cluster-wide
  }
  siva = {
    principal_arn = "arn:aws:iam::359367063384:user/Siva"
    policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    namespaces    = null
  }
  deployer = {
    principal_arn = "arn:aws:iam::359367063384:role/pixnest-deployer"
    policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
    namespaces    = ["pixnest"] # a list scopes the policy to those namespaces
  }
}
```

Add an entry, open a pull request, and the plan shows exactly who is being granted what. Apply and
it exists. Remove the entry and apply, and the access is gone. Nothing is granted by a human
running a command that leaves no trace.

**Why the pipeline role is listed explicitly.** The module can grant cluster-admin to the
"cluster creator" automatically, but that means *whoever runs Terraform* - the pipeline role from
CI, and your own ARN from a laptop. The configuration then plans differently depending on who runs
it, and a local plan proposes destroying and recreating the entry. This project sets
`enable_cluster_creator_admin_permissions = false` and lists every principal instead, so the plan
is identical everywhere.

**Renaming without destroying.** If you restructure these, use `terraform state mv` rather than
letting Terraform delete and recreate. Two access entries cannot exist for one principal, so a
delete-then-create can race and fail with `ResourceInUseException`:

```bash
terraform state mv   'module.eks.module.eks.aws_eks_access_entry.this["cluster_creator"]'   'module.eks.module.eks.aws_eks_access_entry.this["pipeline"]'
```

## 5. The imperative way: two AWS CLI commands

Use this to unblock yourself on a cluster you did not declare, or to hand out temporary access.
Anything permanent belongs in section 4.

Two commands. The first says *who*, the second says *what they may do*.

```bash
CLUSTER=pixnest
REGION=ap-south-1
ME=$(aws sts get-caller-identity --query Arn --output text)

# 4a. Who: register the IAM principal with the cluster
aws eks create-access-entry \
  --cluster-name "$CLUSTER" --region "$REGION" \
  --principal-arn "$ME" --type STANDARD

# 4b. What: attach an access policy, scoped to the whole cluster
aws eks associate-access-policy \
  --cluster-name "$CLUSTER" --region "$REGION" \
  --principal-arn "$ME" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

Both are safe to re-run: the first returns `ResourceInUseException` if the entry exists, the
second is idempotent.

> If your ARN contains `assumed-role`, use the **role** ARN instead, not the session ARN. Turn
> `arn:aws:sts::123:assumed-role/MyRole/session` into `arn:aws:iam::123:role/MyRole`. EKS matches
> on the role, and one entry then covers everyone who assumes it.

### Choosing the right policy

Verify the current list with `aws eks list-access-policies --region ap-south-1`. The four that
matter day to day:

| Policy | Grants | Use for |
|--------|--------|---------|
| `AmazonEKSClusterAdminPolicy` | everything, cluster-wide (`cluster-admin`) | platform owners, the bootstrap operator |
| `AmazonEKSAdminPolicy` | full control of most resources, no cluster-scoped config | team leads, per namespace |
| `AmazonEKSEditPolicy` | create/update/delete workloads, no RBAC changes | developers deploying to their namespace |
| `AmazonEKSViewPolicy` | read-only | students, auditors, on-call reading logs |

AWS also ships narrower ones (`AmazonEKSSecretReaderPolicy`, `AmazonEKSAdminViewPolicy` and a
long tail for other AWS services). Grant the narrowest that lets the person do their job.

### Scoping to one namespace

The default above is cluster-wide. For a developer who should only touch the app namespace:

```bash
aws eks associate-access-policy \
  --cluster-name pixnest --region ap-south-1 \
  --principal-arn arn:aws:iam::359367063384:role/developer \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy \
  --access-scope type=namespace,namespaces=pixnest
```

A deploy pipeline is the usual case: scoped this way it can roll out the app in its own
namespace and cannot read secrets anywhere else in the cluster.

## 6. Write the kubeconfig

```bash
aws eks update-kubeconfig --name pixnest --region ap-south-1
```

It prints where it wrote:

```
Updated context arn:aws:eks:ap-south-1:359367063384:cluster/pixnest in ~/.kube/config
```

This is a **local file operation only**. It succeeds even with no cluster access at all, which is
why a successful `update-kubeconfig` tells you nothing about whether kubectl will work. The file
records the API endpoint, the cluster CA certificate, and a command for kubectl to run to fetch a
token. It stores no long-lived credential: the token is minted on every call from your current
AWS identity, which is also why changing `AWS_PROFILE` changes who you are to the cluster.

Useful context commands when you have more than one cluster:

```bash
kubectl config get-contexts
kubectl config current-context
kubectl config use-context arn:aws:eks:ap-south-1:359367063384:cluster/pixnest

# friendlier name
aws eks update-kubeconfig --name pixnest --region ap-south-1 --alias pixnest-dev
```

## 7. Verify

```bash
kubectl get nodes
kubectl get ns
kubectl auth can-i '*' '*' --all-namespaces   # 'yes' for a cluster admin
kubectl auth can-i delete nodes
kubectl auth can-i create deployments --namespace pixnest
```

`kubectl auth can-i` asks the API server what *you* may do. It is the fastest way to confirm a
policy landed, and the fastest way to prove a scoped policy is genuinely limited.

> **Give it a moment.** Policy associations take a few seconds to reach the authorizer. It is
> normal for `kubectl get nodes` to answer `Forbidden` immediately after `associate-access-policy`
> and to succeed shortly after. Do not start re-granting things in the gap.

## 8. What the bootstrap script does for you

[`scripts/bootstrap-cluster.sh`](scripts/bootstrap-cluster.sh) automates sections 5 and 6 as its
first two stages, then installs the platform layer. It grants to whoever runs it, which is what
you want when that person is not in `access_entries`:

```bash
./infra/scripts/bootstrap-cluster.sh pixnest-boot
```

In order: `update-kubeconfig`; an admin access entry for whoever is running it; the gp3 default
StorageClass; metrics-server; the AWS Load Balancer Controller; Argo CD; the private-repo
credential; and the app-of-apps root. It
is idempotent, so re-running it after a manual fix is safe.

Run the steps by hand once before you trust the script. It hides exactly the two commands most
people get wrong. For anyone who needs access permanently, prefer section 4: an entry the script
creates is invisible to Terraform and vanishes at the next rebuild.

## 9. Adding a colleague or a student

They need two things: an AWS identity in this account, and an access entry.

```bash
# 1. an entry for their IAM user or (better) a shared role
aws eks create-access-entry --cluster-name pixnest --region ap-south-1 \
  --principal-arn arn:aws:iam::359367063384:user/student1 --type STANDARD

# 2. read-only, cluster-wide
aws eks associate-access-policy --cluster-name pixnest --region ap-south-1 \
  --principal-arn arn:aws:iam::359367063384:user/student1 \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
  --access-scope type=cluster
```

Then they run sections 2, 6 and 7 on their own machine. They do **not** need any AWS
console permission beyond `eks:DescribeCluster`, which `update-kubeconfig` calls.

Prefer a role over per-user entries once there is more than one person. One entry for
`arn:aws:iam::…:role/eks-viewer` covers everyone who can assume it, and access is revoked by
changing the role's trust policy rather than by editing the cluster.

## 10. Removing access

```bash
# drop one policy but keep the entry
aws eks disassociate-access-policy --cluster-name pixnest --region ap-south-1 \
  --principal-arn <arn> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy

# remove the principal entirely
aws eks delete-access-entry --cluster-name pixnest --region ap-south-1 --principal-arn <arn>
```

Never delete the node group entry (`EC2_LINUX`) or the AWS service-linked role entry. Removing
the node entry stops every node from authenticating and the cluster goes NotReady.

## 11. Troubleshooting

The single most useful diagnostic is **which** of the two failures you get. They mean opposite
things, and this is exactly the progression you see while setting access up:

| kubectl says | Meaning | Fix |
|--------------|---------|-----|
| `the server has asked for the client to provide credentials` / `Unauthorized` | EKS does not recognise your IAM identity at all | no access entry exists - see section 4 or 5 |
| `Error from server (Forbidden): ... cannot list resource "nodes"` | EKS knows who you are, Kubernetes says no | entry exists with no policy, or too narrow a policy or scope - attach or widen one |

`Unauthorized` is an authentication problem. `Forbidden` is an authorization problem, and it is
progress: it means the access entry exists.

Other failures:

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Unable to connect to the server: dial tcp ... i/o timeout` | your IP is not in the cluster's public access CIDRs | check `publicAccessCidrs` below, and the environment's `public_access_cidrs` tfvar |
| `InvalidClientTokenId` from any aws command | stale `AWS_ACCESS_KEY_ID` env vars overriding the profile | `unset` them, as in step 2 |
| Works, then stops after a while | assumed-role session expired, or your public IP changed | re-authenticate; for the IP, update the tfvar and apply |
| `error: You must be logged in to the server` right after granting | association has not propagated | wait a few seconds and retry |
| kubectl hits the wrong cluster | context left over from another cluster | `kubectl config current-context` |

Check what the cluster's endpoint allows:

```bash
aws eks describe-cluster --name pixnest --region ap-south-1 \
  --query 'cluster.resourcesVpcConfig.[endpointPublicAccess,publicAccessCidrs,endpointPrivateAccess]'
```

dev allows `0.0.0.0/0`, so any network works. prod is restricted to a single address, so a
changed home IP is the most likely reason kubectl stops working there. If public access is turned
off entirely, the API resolves only inside the VPC and you need a VPN, a bastion host or an SSM
port-forward.

## 12. Why access entries and not the aws-auth ConfigMap

Worth knowing, because most older tutorials and a lot of existing clusters still use the
ConfigMap.

| | `aws-auth` ConfigMap (legacy) | Access entries (this cluster) |
|---|---|---|
| Where it lives | a ConfigMap in `kube-system` | the EKS API |
| Editing it | `kubectl edit` on live YAML | `aws eks` commands, or Terraform |
| Audit trail | none | CloudTrail |
| Chicken-and-egg | you need cluster access to grant cluster access | none, it is an AWS API call |
| Failure mode | one bad edit locks everyone out, permanently | an entry can always be re-created |

`authentication_mode` can be `CONFIG_MAP`, `API_AND_CONFIG_MAP`, or `API`. This project uses
`API`, set in [`terraform/modules/eks/main.tf`](terraform/modules/eks/main.tf). Migrating an
existing cluster means moving to `API_AND_CONFIG_MAP` first, recreating each mapping as an access
entry, then switching to `API`.


