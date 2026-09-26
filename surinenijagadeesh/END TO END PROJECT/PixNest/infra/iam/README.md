# IAM policies, as files you can apply

The two GitHub Actions roles this project uses, written as plain JSON so they can be
applied directly with the AWS CLI or pasted into the console. The explanation of what each
one does and why lives in [`../../docs/IAM-ROLES-AND-POLICIES.md`](../../docs/IAM-ROLES-AND-POLICIES.md).

This mirrors how the AWS Load Balancer Controller policy is handled in
[`../terraform/modules/alb-controller/iam_policy.json`](../terraform/modules/alb-controller/iam_policy.json):
the policy is a real file, not a string buried in HCL, so it can be read and diffed.

## What is here

| File | Role it belongs to | Kind | Created by |
|---|---|---|---|
| `pixnest-tf-trust-policy.json` | `pixnest-tf`, the Terraform pipeline | trust | **you, by hand, once** |
| `pixnest-tf-least-privilege-policy.json` | `pixnest-tf` | permissions | **optional**, see below |
| `pixnest-gha-trust-policy.json` | `pixnest-gha`, the application pipeline | trust | Terraform |
| `pixnest-gha-ecr-policy.json` | `pixnest-gha` | permissions | Terraform |

Only the first is genuinely required by hand. It is the bootstrap role, and it has to exist
before Terraform can run at all, because Terraform is what creates everything else. The
other two are here so you can create that role manually as an exercise, or rebuild it when
Terraform is not available.

## What `pixnest-tf` is actually allowed to do

By default, **everything**. The bootstrap attaches the AWS managed `AdministratorAccess`,
which is why there was no permission file here for a long time and why people kept looking
for one.

That is a deliberate teaching-build choice. Terraform in this project creates a VPC, an EKS
cluster, IAM roles, registries and buckets, and writing a least privilege policy that covers
all of it, and keeping it correct as the code changes, is a project in itself. What bounds
the damage is the trust policy: only workflows in this repository can assume the role at all.

`pixnest-tf-least-privilege-policy.json` is the alternative for anyone who does not want
an administrator role sitting in their account. Read the next section before using it.

### Read this before using the least privilege policy

**It has not been proven against a full apply.** It was written from the resources this
project's Terraform actually creates, and the environment was already destroyed when it was
written, so there was nothing to run a real `terraform apply` against. Treat it as a
reviewed starting point, not a finished artifact.

What it does, compared to `AdministratorAccess`:

- Confines networking, compute, logging and key management to **one region**.
- Confines registry changes to repositories named `pixnest-*`.
- Confines IAM to roles and policies named `pixnest-*`, and only lets those roles be
  handed to three named AWS services.
- Explicitly **denies** creating users, access keys, login profiles, identity providers, and
  anything at the organisation or account level. That deny is the important part: it is what
  stops a compromised pipeline from minting itself a permanent identity.

What it still does not solve: a role that can create IAM roles can create a *more powerful*
role. The proper fix is a **permissions boundary** attached to every role this policy is
allowed to create, so nothing it makes can exceed it. That is the next thing to add, and it
is deliberately not here, because a boundary that is wrong is worse than one that is absent.

### The right way to produce one of these

Do not hand write it, which is exactly what was done here and why the warning above exists.
Run the pipeline with the broad policy, let CloudTrail record what it genuinely called, then
generate a policy from that activity and review it:

```
IAM console -> Roles -> pixnest-tf -> Generate policy based on CloudTrail events
```

Pick a window that contains at least one full apply **and** one full destroy, because
destroy calls actions that apply never does. Then diff the generated policy against this
file and keep whichever is tighter, action by action.

### Applying it instead of AdministratorAccess

```bash
aws iam put-role-policy   --role-name pixnest-tf   --policy-name pixnest-tf-least-privilege   --policy-document file:///tmp/iam/pixnest-tf-least-privilege-policy.json

aws iam detach-role-policy   --role-name pixnest-tf   --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

Attach the new policy **before** detaching the old one, and run a plan and an apply before
you walk away. If something is missing you will see an explicit access denied naming the
action, which you then add. Re-attaching `AdministratorAccess` is the one-line rollback.

## Source of truth, and the drift risk

**Terraform is the source of truth for the two `pixnest-gha` files.** They are generated
from `aws_iam_policy_document` blocks in
[`../terraform/modules/github-oidc/main.tf`](../terraform/modules/github-oidc/main.tf), so
if you change the module, change these to match. Being honest about it: duplicated policy
can drift, and this pair is the place it would happen.

The bootstrap trust policy is different. Its real source is the heredoc inside
[`../scripts/bootstrap-aws.sh`](../scripts/bootstrap-aws.sh), and this file is the readable
copy of it.

## Fill in the placeholders first

Every file uses four placeholders. None of them will work as-is.

| Placeholder | Meaning | Example |
|---|---|---|
| `ACCOUNT` | your AWS account id, 12 digits | `359367063384` |
| `REGION` | the region you build in | `ap-south-1` |
| `OWNER` | your GitHub username or organisation | `JAGADEESH-2809` |
| `REPO` | the repository name | `pixnest` |

Substitute them into a working copy rather than editing these files, so the originals stay
reusable:

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-south-1
OWNER=JAGADEESH-2809
REPO=pixnest

mkdir -p /tmp/iam
for f in *.json; do
  sed -e "s/ACCOUNT/$ACCOUNT/g" -e "s/REGION/$REGION/g" \
      -e "s/OWNER/$OWNER/g"     -e "s/REPO/$REPO/g" "$f" > "/tmp/iam/$f"
done
```

Check one before you use it. A policy with an unsubstituted placeholder is accepted by IAM
and then silently matches nothing:

```bash
cat /tmp/iam/pixnest-tf-trust-policy.json
```

## Creating the bootstrap role

The OIDC identity provider must exist first. See step 1 of the doc, or just run
`../scripts/bootstrap-aws.sh`, which does all of this and is idempotent.

```bash
aws iam create-role \
  --role-name pixnest-tf \
  --assume-role-policy-document file:///tmp/iam/pixnest-tf-trust-policy.json \
  --description "GitHub Actions Terraform pipeline (OIDC)"

aws iam attach-role-policy \
  --role-name pixnest-tf \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

To update the trust policy on a role that already exists, rather than recreating it:

```bash
aws iam update-assume-role-policy \
  --role-name pixnest-tf \
  --policy-document file:///tmp/iam/pixnest-tf-trust-policy.json
```

## Creating the application role by hand

Only needed if you are not using Terraform. Normally the `github-oidc` module does this.

```bash
aws iam create-role \
  --role-name pixnest-gha \
  --assume-role-policy-document file:///tmp/iam/pixnest-gha-trust-policy.json \
  --description "GitHub Actions application pipeline (OIDC), ECR push only"

aws iam put-role-policy \
  --role-name pixnest-gha \
  --policy-name pixnest-gha-ecr \
  --policy-document file:///tmp/iam/pixnest-gha-ecr-policy.json
```

## Two things in these files that look like mistakes and are not

**`ecr:GetAuthorizationToken` is on `"*"`.** It is not a resource-scopeable action. Pinning
it to a repository ARN produces a policy that reads as more careful and then fails at
`docker login` with an access denied that names no resource at all.

**The subject condition contains `@*` wildcards.** Some GitHub accounts emit an immutable-id
form of the subject claim, `repo:owner@12345/repo@67890:...`, which a plain
`repo:OWNER/REPO:*` pattern does not match. The workflow then fails with
`Not authorized to perform sts:AssumeRoleWithWebIdentity` while every name in the pattern is
spelled correctly. The wildcard form matches both shapes.

Never widen the subject condition further than this. It is the only thing stopping any
repository on GitHub from assuming your role, and it matters far more than the permission
policy does.

## Checking a policy before you trust it

Creating a role always succeeds. Whether it authenticates only shows up on the next
pipeline run, so verify deliberately:

```bash
# what the role actually trusts
aws iam get-role --role-name pixnest-tf \
  --query 'Role.AssumeRolePolicyDocument' --output json

# what the application role may actually do
aws iam get-role-policy --role-name pixnest-gha --policy-name pixnest-gha-ecr \
  --query 'PolicyDocument' --output json
```

If a pipeline fails to assume a role, the rejected call is recorded in CloudTrail. Filter
Event history on `AssumeRoleWithWebIdentity` and read the subject that was actually
presented, rather than guessing at the pattern.


