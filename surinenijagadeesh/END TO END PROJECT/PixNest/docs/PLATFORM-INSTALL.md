# Installing the platform layer by hand, one command at a time

`bootstrap-cluster.sh` does all of this in about four minutes. This page is the same work done
**manually, in front of a class**, so every step can be explained, broken and questioned before
moving on. Run the script when you want the cluster up; run this when you want people to
understand what the script does.

Starting point: an EKS cluster created by the Terraform pipeline
([EKS-DEPLOY.md](../infra/EKS-DEPLOY.md) stage 1), with working kubectl access
([CLUSTER-ACCESS.md](../infra/CLUSTER-ACCESS.md)). Finishing point: the full application running and
reachable on a public URL, managed by GitOps.

Every command and every output below was run against the live `pixnest` cluster.

---

## Step 0: show them the cluster is empty

```bash
kubectl get ns
kubectl get storageclass
helm list -A
```

Four namespaces, no Helm releases, and exactly one StorageClass:

```
NAME   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
gp2    kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false
```

**Teaching point, and the first real trap.** EKS still ships that `gp2` class, and its provisioner
is `kubernetes.io/aws-ebs` - the *in-tree* driver that Kubernetes **removed in 1.31**. It looks
like a working default. It is not. Any PersistentVolumeClaim against it stays `Pending` forever,
with an error that says nothing about removed drivers. The Postgres StatefulSet later in this
guide would hang on exactly that.

## Step 1: a StorageClass that actually provisions

```bash
kubectl apply -f infra/platform/storageclass.yaml
kubectl patch storageclass gp2 \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl get storageclass
```

```
NAME            PROVISIONER       RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
gp2             kubernetes.io/aws-ebs   Delete    WaitForFirstConsumer   false
gp3 (default)   ebs.csi.aws.com   Delete          WaitForFirstConsumer   true
```

Worth pausing on three fields in that file:

- `provisioner: ebs.csi.aws.com` - the CSI driver, installed by Terraform as an EKS add-on. The
  driver gets its AWS permissions from EKS Pod Identity, not from node credentials.
- `volumeBindingMode: WaitForFirstConsumer` - do not create the EBS volume until a pod is
  scheduled, so the volume lands in the **same availability zone** as the pod. With the default
  `Immediate` you eventually get a volume in one zone and a pod that can only run in another.
- `allowVolumeExpansion: true` - you can grow the volume later. `gp2` above says `false`, and you
  cannot change that after the fact.

## Step 2: metrics-server

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update metrics-server
helm upgrade --install metrics-server metrics-server/metrics-server \
  -n kube-system --version 3.14.0 --wait --timeout 5m
kubectl top nodes
```

```
NAME                         CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
ip-10-0-15-24.ec2.internal   110m         5%       1196Mi          38%
ip-10-0-26-49.ec2.internal   58m          3%       1367Mi          43%
```

**Why it is here.** Kubernetes ships **no** metrics pipeline. Without this, `kubectl top` fails
and every HorizontalPodAutoscaler reports `cpu: <unknown>/70%` and never scales. The backend chart
declares an HPA, so skipping this step leaves Argo CD showing the backend as **Degraded** with no
obvious cause - a confusing thing to hit live. Install it before the app, not after.

## Step 3: the AWS Load Balancer Controller

### What must already be true

The helm install below is four commands, but it only works because six things are already in
place. Five come from Terraform; one is a property of the chart values. Check them before you
start, because every one of them fails in a different and non-obvious way. The full reasoning,
the request path, and how to debug each failure is in [INGRESS-AND-ALB.md](INGRESS-AND-ALB.md).

| # | Prerequisite | Created by | If it is missing |
|---|--------------|------------|------------------|
| 1 | IAM role `<prefix>-alb-controller`, trusted by `pods.eks.amazonaws.com` | `modules/alb-controller` | controller pod runs but every AWS call is AccessDenied |
| 2 | The controller's published IAM policy, attached to that role | `modules/alb-controller`, vendored `iam_policy.json` | same, and the logs name the exact action it lacked |
| 3 | Pod Identity association for `kube-system/aws-load-balancer-controller` | `modules/alb-controller` | no credentials reach the pod at all |
| 4 | The `eks-pod-identity-agent` add-on running on the cluster | `modules/eks` `addons` | the association exists but nothing delivers the token |
| 5 | Subnet tags `kubernetes.io/role/elb=1` on the public subnets | `modules/vpc` | Ingress stays pending, "unable to discover subnets" |
| 6 | A NetworkPolicy that admits the **VPC CIDR**, not an ingress namespace | `values.yaml` `allowFromCIDR` | **the silent one**: pods healthy, ALB created, targets permanently unhealthy, page never loads |

Numbers 4 and 6 are the ones that catch people. The Pod Identity agent is easy to forget because
it is invisible until something needs it. Number 6 is worse: with `target-type: ip` the ALB
delivers from its own network interfaces in the VPC straight to pod IPs, so a NetworkPolicy
written for an in-cluster nginx selects a namespace that the traffic never comes from, and drops
both the requests and the health checks while everything *looks* fine.

Verify the lot in one go:

```bash
aws iam get-role --role-name pixnest-alb-controller --query 'Role.RoleName'
aws eks list-pod-identity-associations --cluster-name pixnest --region ap-south-1   --query "associations[?serviceAccount=='aws-load-balancer-controller']"
aws eks list-addons --cluster-name pixnest --region ap-south-1        # expect eks-pod-identity-agent
VPC=$(aws eks describe-cluster --name pixnest --region ap-south-1   --query 'cluster.resourcesVpcConfig.vpcId' --output text)
aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC   --query 'Subnets[].[SubnetId,Tags[?Key==`kubernetes.io/role/elb`].Value|[0]]' --output text
aws ec2 describe-vpcs --vpc-ids $VPC --query 'Vpcs[0].CidrBlock'       # must match allowFromCIDR
```

Note the last one: the VPC CIDR is currently written into the chart values by hand, so if an
environment ever changes its CIDR the NetworkPolicy must change with it.

### Install it

```bash
CLUSTER=pixnest
REGION=ap-south-1
VPC_ID=$(aws eks describe-cluster --name $CLUSTER --region $REGION \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --version 3.5.0 \
  --set clusterName=$CLUSTER --set region=$REGION --set vpcId=$VPC_ID \
  --wait --timeout 10m

kubectl -n kube-system get deploy aws-load-balancer-controller
kubectl get ingressclass
```

**What this controller is.** It watches `Ingress` objects and creates real **Application Load
Balancers** to match. Nothing happens yet, because no Ingress exists; the ALB appears in step 6
when Argo CD deploys the app.

**Where its AWS permissions come from.** It calls the ELB, EC2 and ACM APIs, so it needs real
credentials. Terraform already created an IAM role and a Pod Identity association binding
`kube-system/aws-load-balancer-controller` to it, in
[`infra/terraform/modules/alb-controller`](../infra/terraform/modules/alb-controller/). That is why there is no
`eks.amazonaws.com/role-arn` annotation anywhere here and no access key in sight. Prove it once
the pod is up:

```bash
kubectl -n kube-system exec deploy/aws-load-balancer-controller -- env | grep AWS_CONTAINER
```

**Why ALB rather than nginx**, what the annotations buy, and the full request path are covered
in [INGRESS-AND-ALB.md](INGRESS-AND-ALB.md). The short version: nginx would run a proxy you
operate behind a classic load balancer and add a hop; the ALB is AWS-native, terminates TLS with
an ACM certificate, and with `target-type: ip` delivers straight to pod IPs. It only exists on
AWS, which is why minikube keeps nginx.

## Step 4: Argo CD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace   --version 10.9.0 -f infra/platform/argocd/values.yaml --wait --timeout 10m

kubectl get pods -n argocd
```

Seven pods: the application controller, repo server, API server, ApplicationSet controller,
notifications controller, Redis and Dex.

**Getting into the UI**, the admin password, the CLI, and the optional public ALB are all in
[../infra/platform/argocd/README.md](../infra/platform/argocd/README.md). The short version:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80   # then http://localhost:8080
kubectl -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode}}'   # user: admin
```

**Why the Helm chart rather than the raw manifest.** The Argo CD project publishes a single
`install.yaml` and `kubectl apply -f` on it works. It is the wrong choice here, for four reasons:

- **Configuration.** The manifest is fixed. Changing anything - insecure mode, an Ingress,
  resource limits, HA - means patching objects afterwards, and the next apply undoes the patch.
  With the chart it is a values file under version control.
- **Versioning.** That URL says `stable`, so what you install today is not what you install next
  month. `--version 10.9.0` pins it.
- **Upgrades and rollback.** Helm records every revision, so `helm history` shows what changed and
  `helm rollback` undoes it. Raw manifests have neither.
- **Clean removal.** `helm uninstall` removes exactly what it installed. After `kubectl apply` you
  are deleting objects by hand and guessing which were yours.

The raw manifest is still worth opening in a class. It is one file listing every object Argo CD
needs, which the chart hides behind templates.

**What the chart does and does not create.** It installs the CRDs (`crds.install: true`) and
deliberately **keeps** them on uninstall (`crds.keep: true`), because deleting a CRD deletes every
object of that kind, which would mean every Application you have defined. A good default, and
worth pointing out.

It creates **no Ingress**: `values.yaml` sets `ingress.enabled: false`, so Argo CD is reachable
only through a local tunnel. Putting it on a public ALB is an opt-in overlay with real security
and cost consequences, covered in
[../infra/platform/argocd/README.md](../infra/platform/argocd/README.md) and
[INGRESS-AND-ALB.md](INGRESS-AND-ALB.md) section 8.

**Why Terraform does not install this.** Terraform owns cloud resources; the cluster's own
software is installed here; the application is owned by Git. Folding Argo CD into Terraform would
tie tearing down the cluster to tearing down the apps, and would need a live kubeconfig during
`terraform apply`.

## Step 5: let Argo CD read the private repo

The repository is private, so Argo CD needs a credential. **Use a read-only deploy key**: it
belongs to the repository rather than to a person, and it cannot write.

No special tooling needed. `ssh-keygen` ships with Windows, macOS and Linux, and the rest is a
browser.

**1. Generate a keypair**, with no passphrase, because nothing can type one for Argo CD.

```bash
ssh-keygen -t ed25519 -C "argocd" -f ./argocd_deploy_key -N ""      # bash
ssh-keygen -t ed25519 -C "argocd" -f .\argocd_deploy_key -N '""'    # PowerShell
```

**2. Add the PUBLIC half to the repository, in the browser.** Repository -> **Settings** ->
**Deploy keys** -> **Add deploy key**. Give it a title, paste the contents of
`argocd_deploy_key.pub`, and **leave "Allow write access" unchecked**. Add key.

Paste the `.pub` file. If what you pasted starts `-----BEGIN OPENSSH PRIVATE KEY-----`, that is
the private half: delete it from GitHub and start over with a fresh pair.

**3. Put the PRIVATE half in the cluster.**

```bash
kubectl -n argocd create secret generic pixnest-repo \
  --from-literal=type=git \
  --from-literal=url=git@github.com:JAGADEESH-2809/te-5th_and_6th_batch_assignments.git \
  --from-file=sshPrivateKey=./argocd_deploy_key

kubectl -n argocd label secret pixnest-repo \
  argocd.argoproj.io/secret-type=repository --overwrite
```

**4. Delete the key files from your machine.** They live in the cluster now.

**Teaching point one: the label is not decoration.** Argo CD finds repositories by watching for
secrets labelled `argocd.argoproj.io/secret-type=repository`. Without it the secret is ignored and
the Application reports `repository not accessible`, with the credential sitting right there in
the namespace.

**Teaching point two: the URL must match exactly.** Argo CD pairs a credential to a repository by
URL string, so an SSH credential does not apply to an `https://` Application:

```
failed to list refs: authentication required: Repository not found.
```

That reads like a missing repository, but it is a URL mismatch. Every `repoURL` under
`infra/argocd/` uses `git@github.com:...` for this reason.

**Teaching point three: read-only is a real guarantee.** Prove it in front of them:

```
$ git push        # using the deploy key
ERROR: The key you are authenticating with has been marked as read only.
```

Even if the cluster is compromised, that credential cannot rewrite the source of truth. A personal
token can.

**If the repository were public**, none of this exists: no key, no secret, no label. Worth saying
out loud, because it is the simplest answer whenever the material is not sensitive.

**Alternatives** - a fine-grained token created entirely in the browser, a GitHub App for
organisation scale, and where the secret itself should really live - are in
[GIT-REPO-ACCESS.md](GIT-REPO-ACCESS.md).

## Step 6: hand over to GitOps

One manifest. Everything else comes from Git.

```bash
kubectl apply -f infra/argocd/application.yaml
kubectl -n argocd get applications -w
```

```
NAME                 SYNC STATUS   HEALTH STATUS
pixnest            Synced        Healthy
pixnest-postgres   Synced        Healthy
pixnest-backend    Synced        Healthy
pixnest-frontend   Synced        Healthy
```

That single Application points at `infra/argocd/apps/`, a directory of three more Applications.
This is the **app-of-apps** pattern: bootstrap one object, and it manages the rest. The three
carry `argocd.argoproj.io/sync-wave` annotations, so they roll out in order - postgres (wave 0),
then backend (wave 1), then frontend (wave 2). Without waves the backend would start against a
database that does not exist yet.

Expect the backend to `CrashLoopBackOff` once or twice while Postgres finishes starting. That is
the sync wave doing its job, not a failure. It recovers on its own:

```
pixnest-backend-...   0/1   CrashLoopBackOff   1 (12s ago)
pixnest-backend-...   1/1   Running            2 (38s ago)
```

## Step 7: prove it works

```bash
kubectl -n pixnest get pods,pvc,ingress,hpa
kubectl -n pixnest get ingress pixnest \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

The address now comes from the **Ingress** itself, not from a controller Service. That is the
visible difference from the nginx model: the ALB belongs to the Ingress.

Open that hostname. Register, log in, upload a photo. Or from a terminal, which is easier to show
on a projector:

```bash
URL=http://$(kubectl -n pixnest get ingress pixnest \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -X POST "$URL/api/auth/register" -H 'Content-Type: application/json' \
  -d '{"username":"demo","email":"demo@example.com","password":"TestPass123!"}'

TOKEN=$(curl -s -X POST "$URL/api/auth/login" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'username=demo' --data-urlencode 'password=TestPass123!' \
  | python -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

curl -X POST "$URL/api/photos" -H "Authorization: Bearer $TOKEN" -F 'file=@photo.png'
```

**The payoff is in the response.** The upload returns a presigned S3 URL whose credential starts
with `ASIA`, not `AKIA`. `ASIA` means a **temporary** STS credential. The pod was handed it by
EKS Pod Identity seconds earlier, and it expires on its own. There is no access key anywhere in
the pod, the image or the chart. Show the object really landed:

```bash
aws s3 ls s3://pixnest-photos-<account-id>/ --recursive
```

Note the split: the **file** is in S3, the **metadata** is in Postgres on an EBS volume.

## Step 8: the finale, self-healing

```bash
kubectl -n pixnest delete deploy pixnest-backend
kubectl -n pixnest get pods -w
```

Argo CD notices the drift and puts it back, because `selfHeal: true`. Deleting things from the
cluster does not change anything, because the cluster is not the source of truth. **Git is.**

## When you are done

Tear down in the reverse order of creation, and delete what Kubernetes created in AWS *before*
running the Terraform destroy:

```bash
kubectl delete ingress -A --all      # removes the ALB and its security groups
kubectl delete svc -A --field-selector spec.type=LoadBalancer
kubectl -n pixnest delete pvc --all
```

The Ingress line matters now: with the ALB controller the load balancer hangs off the **Ingress**,
so deleting Services alone leaves it behind to block the VPC delete.

Then **Actions -> `terraform` -> Run workflow -> environment `dev`, action `destroy`**, typing
`dev` into the confirm box. Full detail in [EKS-DEPLOY.md](../infra/EKS-DEPLOY.md).

## Quick reference

| Step | What | Time | Creates something billable? |
|------|------|------|------------------------------|
| 1 | gp3 StorageClass | instant | no |
| 2 | metrics-server | ~30s | no |
| 3 | AWS Load Balancer Controller | ~2 min | no, not until an Ingress exists |
| 4 | Argo CD | ~1 min | no |
| 5 | repo credential | instant | no |
| 6 | app-of-apps | ~2 min | **yes, the ALB and an EBS volume for Postgres** |

