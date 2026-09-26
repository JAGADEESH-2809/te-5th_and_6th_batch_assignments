# IAM roles and policies

Every identity this project uses, what it is allowed to do, and why. Nothing here is
optional reading if you are rebuilding the project in your own AWS account: without these
roles the pipeline cannot deploy and the application cannot reach S3.

There are five identities. Two are for CI/CD and three run inside the cluster. One is
created by hand, and the other four are created by Terraform.

| Identity | Who uses it | Created by | How it authenticates |
|---|---|---|---|
| pixnest-tf | the Terraform pipeline | you, by hand, once | GitHub OIDC |
| pixnest-gha | the application CI pipeline | Terraform | GitHub OIDC |
| pixnest-backend | the backend pod | Terraform | EKS Pod Identity |
| pixnest-alb-controller | the load balancer controller pod | Terraform | EKS Pod Identity |
| pixnest-ebs-csi | the EBS CSI driver pod | Terraform | EKS Pod Identity |

The two GitHub Actions policies are also checked in as applyable JSON, in
[`../infra/iam/`](../infra/iam/), so you can create the roles with one CLI command instead
of retyping them out of this page.

Two ideas explain the whole table. **Nothing holds a long lived access key.** Both
pipelines and all three pods receive short lived credentials that AWS mints on demand and
expires on its own. And **the order matters**, because one role has to exist before
Terraform can run at all, since Terraform is what creates the other four.

---

## The chicken and egg problem

Terraform builds the infrastructure. But Terraform needs somewhere to keep its state, and
GitHub Actions needs permission to run Terraform. Neither of those can be built by the
thing that needs them.

So exactly three things are created once, by hand, with admin credentials. This is the
bootstrap, or stage zero:

1. An S3 bucket for Terraform state, versioned, encrypted and private.
2. The GitHub OIDC identity provider.
3. The pixnest-tf role, which the pipeline assumes.

Everything after that is Terraform's job. The script that does all three is
`infra/scripts/bootstrap-aws.sh`, and it is safe to re-run. The sections below give the
console steps and the raw JSON, so you can do it by hand and understand what the script is
doing rather than watching it scroll past.

Substitute your own values throughout:

| Placeholder | Meaning | Example |
|---|---|---|
| ACCOUNT | your AWS account id, 12 digits | 359367063384 |
| REGION | the region you build in | ap-south-1 |
| OWNER | your GitHub username or organisation | JAGADEESH-2809 |
| REPO | the repository name | pixnest |

---

## Step 1: the GitHub OIDC identity provider

This is what lets GitHub Actions prove who it is to AWS with no stored secret. GitHub signs
a short lived token describing the workflow that is running, and AWS verifies that
signature against this provider.

You create it once per AWS account, not once per repository.

**In the console.** Open IAM, then Identity providers in the left sidebar, then Add
provider. Choose OpenID Connect. For Provider URL enter
`https://token.actions.githubusercontent.com` and click Get thumbprint. For Audience enter
`sts.amazonaws.com`. Then Add provider.

**On the command line.**

```bash
aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 1c58a3a8518e8759bf075b76b750d4f2df264fcd
```

An EntityAlreadyExists error means it is already there and you have nothing to do.

---

## Step 2: the pixnest-tf role, by hand

This is the role the Terraform pipeline assumes, and the only role you create yourself.

### Trust policy: who may assume it

The trust policy is the important half. It is the only thing standing between "my GitHub
Actions can build my infrastructure" and "anyone on GitHub can build in my account".

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:OWNER@*/REPO@*:*"
        }
      }
    }
  ]
}
```

This policy is checked in at
[`../infra/iam/pixnest-tf-trust-policy.json`](../infra/iam/pixnest-tf-trust-policy.json).

Read the two conditions. The audience check confirms the token was minted for AWS and not
for some other service. The subject check confirms which repository the workflow runs in.
Drop the subject condition and any repository on GitHub could assume your role, so never
put a bare wildcard there.

### The subject claim gotcha

The two `@*` wildcards are not decoration. Some GitHub accounts emit an **immutable id**
form of the subject claim:

```
repo:JAGADEESH-2809@12345/pixnest@67890:ref:refs/heads/main
```

instead of the documented form:

```
repo:JAGADEESH-2809/te-5th_and_6th_batch_assignments:ref:refs/heads/main
```

A plain `repo:OWNER/REPO:*` pattern does not match the first form, and the failure is
confusing. The workflow fails with `Not authorized to perform sts:AssumeRoleWithWebIdentity`
even though every name in your pattern is spelled correctly. This project hit exactly that.

Writing the pattern as `repo:OWNER@*/REPO@*:*` matches both forms, so it works either way.

If you would rather read the real subject than guess, the simplest place to find it is the
failed run itself. AWS CloudTrail records the rejected `AssumeRoleWithWebIdentity` call,
and the event includes the subject that was presented. Open CloudTrail, then Event history,
filter on the event name, and read it from the request parameters.

### Permissions: what it may do

pixnest-tf gets **AdministratorAccess**.

That deserves an honest explanation rather than a quiet attachment. Terraform here creates
a VPC, an EKS cluster, IAM roles, ECR repositories and S3 buckets. Writing a least
privilege policy covering all of that, and keeping it correct as the code changes, is a
real project in itself.

What bounds the damage is not the permission policy but the trust policy. Only workflows in
your repository can assume this role at all.

In production you would narrow it, and you would separate plan from apply so the plan role
is read only and a pull request can never change anything. Say that out loud when teaching
this, because copying AdministratorAccess into a real account without the context is how
accidents happen.

### Creating it

**In the console.** IAM, then Roles, then Create role. Choose Web identity as the trusted
entity type. Pick the `token.actions.githubusercontent.com` provider and `sts.amazonaws.com`
as the audience. The console asks for an organisation and repository; fill anything in,
because the next step replaces the whole trust policy. Attach AdministratorAccess, name the
role `pixnest-tf`, and create it. Then open the role, go to the Trust relationships tab,
click Edit trust policy, and paste the JSON above.

**On the command line**, with the trust policy saved as `trust.json`:

```bash
aws iam create-role --role-name pixnest-tf --assume-role-policy-document file://trust.json --description "GitHub Actions Terraform pipeline (OIDC)"
aws iam attach-role-policy --role-name pixnest-tf --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

---

## Step 3: the repository variables

The pipelines need to know which account, region, role and state bucket to use. None of
these are secrets, so they are repository **variables** rather than repository secrets.
Nothing account specific is committed, which is why this code runs against any AWS account
unchanged.

**In the GitHub UI.** Open the repository, click Settings, then Secrets and variables in
the left sidebar, then Actions, then the Variables tab, then New repository variable.

| Variable | Value |
|---|---|
| AWS_ACCOUNT_ID | ACCOUNT |
| AWS_REGION | REGION |
| AWS_TF_ROLE_ARN | arn:aws:iam::ACCOUNT:role/pixnest-tf |
| AWS_GHA_ROLE_ARN | arn:aws:iam::ACCOUNT:role/pixnest-gha |
| TF_STATE_BUCKET | pixnest-tfstate-ACCOUNT |

AWS_GHA_ROLE_ARN points at a role that does not exist yet. That is deliberate. The name is
predictable, so you set the variable now and Terraform creates the role in the next step.

---

## Step 4: pixnest-gha, created by Terraform

This is the role the **application** CI pipeline assumes to push container images. It is a
separate role from pixnest-tf on purpose: building an image should never carry the
ability to delete a VPC.

Terraform module: `infra/terraform/modules/github-oidc`.

Its trust policy is the same shape as pixnest-tf, pointing at the same OIDC provider with
the same subject condition. The difference is entirely in the permissions. Both are checked
in, at [`../infra/iam/pixnest-gha-trust-policy.json`](../infra/iam/pixnest-gha-trust-policy.json)
and [`../infra/iam/pixnest-gha-ecr-policy.json`](../infra/iam/pixnest-gha-ecr-policy.json).

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:BatchGetImage"
      ],
      "Resource": [
        "arn:aws:ecr:REGION:ACCOUNT:repository/pixnest-backend",
        "arn:aws:ecr:REGION:ACCOUNT:repository/pixnest-frontend"
      ]
    }
  ]
}
```

Two things there are commonly got wrong.

**GetAuthorizationToken must be on a star.** It is not a resource scoped action, so writing
a repository ARN produces a policy that looks careful and then fails at `docker login` with
an access denied that names no resource.

**Everything else is scoped to exactly two repositories.** Push access to those two and
nothing else anywhere in ECR.

That is the whole permission set. The pipeline can push images and read them back. It
cannot create repositories, delete images, or touch any other AWS service.

---

## Step 5: the in-cluster roles, created by Terraform

Three pods need AWS permissions. None of them get an access key, and none of them use the
node's instance role, which would hand every pod on that node the same access.

They use **EKS Pod Identity**, the successor to IRSA. The mechanism is worth stating
plainly, because it explains the trust policy below. You create a normal IAM role that
trusts the EKS service. Then you create an **association** mapping a specific cluster,
namespace and ServiceAccount to that role. An agent on the cluster hands short lived
credentials to pods running under that ServiceAccount, and to nothing else.

The ServiceAccount needs no annotation. That is the visible difference from IRSA, where the
role ARN had to be annotated onto the ServiceAccount itself. Here the mapping lives in the
association, on the AWS side.

All three roles share the same trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "pods.eks.amazonaws.com"
      },
      "Action": [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }
  ]
}
```

`sts:TagSession` is required, not optional. EKS tags the session with the cluster,
namespace and ServiceAccount, which is what makes the association enforceable and what
appears in CloudTrail. Leave it out and the association cannot assume the role.

### pixnest-backend: the application to S3

Module: `infra/terraform/modules/pod-identity`. Associated with the ServiceAccount
`pixnest-backend` in the `pixnest` namespace.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::pixnest-photos-ACCOUNT/*"
    },
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::pixnest-photos-ACCOUNT"
    }
  ]
}
```

This is genuine least privilege, and its shape is worth teaching. Object actions apply to
the objects, written as the bucket ARN followed by a slash and a star. ListBucket applies
to the bucket itself, with no trailing slash and no star. Getting those two resource forms
the wrong way round is the most common S3 policy mistake, and it fails in a way that looks
like the permission is missing entirely.

If you encrypt the bucket with a customer managed KMS key, S3 permissions alone are not
enough: every upload needs a data key and every download needs a decrypt. The module adds
that automatically when a key is configured, scoped to that one key and only when S3 is the
calling service.

### pixnest-alb-controller: Ingress objects to real load balancers

Module: `infra/terraform/modules/alb-controller`. Associated with the ServiceAccount
`aws-load-balancer-controller` in the `kube-system` namespace.

The permission set is large, sixteen statements covering EC2, elastic load balancing, ACM,
WAF, Shield and Cognito. It is **published by the controller project** and changes between
releases, so it is not hand written here. The file is vendored at the pinned controller
version, at `infra/terraform/modules/alb-controller/iam_policy.json`.

When you bump the controller, fetch the matching policy deliberately:

```bash
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.5.0/docs/install/iam_policy.json
```

Change the tag to the version you are moving to, and keep it equal to
`alb_controller_version` in the environment's tfvars. A controller running against the
policy from a different release fails in confusing ways, usually when creating a listener
rather than at startup.

### pixnest-ebs-csi: persistent volumes

Defined inside `infra/terraform/modules/eks`. Associated with the ServiceAccount
`ebs-csi-controller-sa` in the `kube-system` namespace.

This one attaches an AWS managed policy rather than a written one:

```
arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
```

It is what lets a PersistentVolumeClaim become a real EBS volume, which is how the Postgres
StatefulSet gets its disk.

One consequence to know, because it bites people at teardown. Volumes created this way are
created by Kubernetes, not by Terraform, so `terraform destroy` does not know they exist
and leaves them behind, still costing money. After destroying a cluster, look for orphans
and delete them:

```bash
aws ec2 describe-volumes --region REGION --filters Name=status,Values=available --output table
```

---

## Who can use kubectl

Cluster access is not IAM policy. An IAM role allowed to call the EKS API is not
automatically allowed to run `kubectl` against the cluster, and this catches almost
everyone once.

This project uses **access entries**, with the cluster's authentication mode set to `API`.
That is the modern replacement for editing the `aws-auth` ConfigMap by hand. Who gets
access is declared in the environment's tfvars in the `access_entries` block, so cluster
admin appears in code review and is rebuilt with the environment rather than granted by
hand afterwards.

See `infra/CLUSTER-ACCESS.md` for the detail, including how to add a new person.

---

## Verifying it all works

Creating a role always succeeds. Whether it authenticates only shows up later, so check
each layer separately.

**The bootstrap role.** The Terraform pipeline's first AWS step either assumes the role or
it does not. A failure reading `Not authorized to perform sts:AssumeRoleWithWebIdentity` is
a trust policy problem, and almost always the subject claim.

**The image push role.** Watch the application pipeline's login and push steps. An access
denied that names no resource usually means GetAuthorizationToken was scoped to a
repository ARN instead of a star.

**The pod roles.** Check the associations exist, then check a pod actually received
credentials:

```bash
aws eks list-pod-identity-associations --cluster-name pixnest --region REGION --output table
kubectl -n pixnest exec deploy/pixnest-backend -- env | grep AWS_
```

A pod that picked up Pod Identity has `AWS_CONTAINER_CREDENTIALS_FULL_URI` and
`AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE` in its environment. If those are missing the
association does not match. Check that the namespace and ServiceAccount name in the
association are exactly the ones the pod runs under, and that the `eks-pod-identity-agent`
add-on is installed and running.

**End to end.** Upload a photo through the application. That one action exercises the
backend role writing to S3, and if the image then appears in the gallery, the presigned URL
reading it back.

---

## What to do differently in production

Stated plainly, so nobody copies the teaching build into something real by accident.

- **Split plan from apply.** Two roles, with the plan role read only, so a pull request
  from a fork can never change infrastructure.
- **Replace AdministratorAccess on pixnest-tf** with a policy scoped to the services this
  project actually manages.
- **Add a permissions boundary.** Without one, permission to create IAM roles is
  effectively permission to escalate to administrator, because a role that can create roles
  can create a more powerful one.
- **Narrow the subject condition** from the whole repository to specific branches or
  environments, so only workflows on `main` can deploy.
- **Require GitHub environment approval** on the apply job, which puts a human between a
  merge and a production change.


