# Ingress: how a URL reaches a pod

Everything about getting outside traffic into this application: which controller does it, why,
what it builds in AWS, what has to be true first, and how each piece fails.

If you only need the install commands, they are step 3 of
[PLATFORM-INSTALL.md](PLATFORM-INSTALL.md). This page is the reasoning behind them.

---

## 1. The shape of the problem

An `Ingress` object is only a **request**. It says "route `/api` here and `/` there". It does
nothing at all on its own. Something has to watch for Ingress objects and build the real thing.
That something is an **ingress controller**, and Kubernetes deliberately ships none.

So the question is never "do I need an Ingress", it is "which controller, and what does it build".

| | nginx ingress controller | AWS Load Balancer Controller |
|---|---|---|
| What it runs | an nginx proxy, in your cluster, as pods you operate | nothing in the data path |
| What it builds in AWS | a `Service type=LoadBalancer`, so a classic ELB or NLB pointing at the proxy | an **Application Load Balancer**, directly |
| Request path | client -> ELB -> nginx pod -> your pod | client -> ALB -> your pod |
| TLS | terminate at nginx, certificates you manage (cert-manager) | terminate at the ALB with an **ACM** certificate |
| Runs where | anywhere Kubernetes runs | AWS only |
| Failure surface | you operate the proxy: its resources, upgrades, config | AWS operates the load balancer |

This project uses the **AWS Load Balancer Controller on EKS**, and keeps nginx for local minikube
only, because the AWS controller cannot exist there. That is the single reason nginx survives in
the repo at all, in `infra/helm/frontend/values-local.yaml`.

## 2. What actually happens when the Ingress appears

1. Argo CD applies the `pixnest` Ingress, from the frontend chart.
2. The controller, watching the API server, sees an Ingress whose `ingressClassName` is `alb`.
3. It reads the annotations to decide what to build, and looks for subnets **by tag**.
4. It calls the AWS APIs and creates an Application Load Balancer, a listener, and one **target
   group per backend Service** in the rules.
5. Because `target-type: ip` is set, it registers **pod IPs** as targets, not node ports.
6. It writes the load balancer's DNS name back onto the Ingress `status`, which is why
   `kubectl get ingress` eventually shows an address.

Two consequences worth saying out loud:

- **The address belongs to the Ingress**, not to a controller Service. With nginx you read the
  address off `svc/ingress-nginx-controller`. Here you read it off the Ingress itself.
- **The ALB is not in Terraform state.** Kubernetes created it through the AWS API. Terraform has
  no idea it exists, which is what makes teardown order matter (section 7).

## 3. The annotations, and what each one buys

From `infra/helm/frontend/values.yaml`, under `albAnnotations`:

| Annotation | Value | Why |
|------------|-------|-----|
| `scheme` | `internet-facing` | public. `internal` gives a VPC-only load balancer. |
| `target-type` | `ip` | register pod IPs directly. Removes the node-port hop, and needs the VPC CNI, which this cluster runs. The alternative, `instance`, routes via node ports. |
| `listen-ports` | `[{"HTTP": 80}]` | plain HTTP today. TLS is section 9. |
| `healthcheck-path` | `/` | both Services answer on `/`, so one setting covers every target group. |
| `group.name` | `pixnest` | **cost control.** Ingresses sharing a group name land on ONE load balancer. Without it, every Ingress provisions its own ALB and the bill scales with the number of Ingress objects. |

The template picks `albAnnotations` or `nginxAnnotations` based on `ingress.className`. They are
kept as separate maps on purpose: Helm deep-merges maps across values files, so a single
`annotations:` block would leave the local nginx render carrying dead `alb.*` keys and the EKS
render carrying nginx ones.

## 4. Where the controller's AWS permissions come from

The controller runs as a pod and calls the ELB, EC2, ACM and WAF APIs. It needs real credentials,
and it gets them the same way the application gets S3 access: **EKS Pod Identity**.

```
ServiceAccount kube-system/aws-load-balancer-controller
        |  (Pod Identity association, created by Terraform)
        v
IAM role <prefix>-alb-controller
        |  (trusts pods.eks.amazonaws.com)
        v
the controller's published IAM policy, vendored at a pinned release
```

No IRSA, no cluster OIDC provider, no `eks.amazonaws.com/role-arn` annotation, and no access key
anywhere. The absence of that annotation is worth pointing at during a demo, because every older
tutorial has one.

The policy lives at `infra/terraform/modules/alb-controller/iam_policy.json`. It is the file the
controller project publishes, copied in at a pinned tag rather than fetched during `apply`, so
plans are reproducible and a permission change shows up as a reviewable diff. It spans
`elasticloadbalancing`, `ec2`, `acm`, `wafv2`, `waf-regional`, `shield`, `cognito-idp` and `iam`.

To upgrade the controller, three things move together: the chart version in the platform layer,
`alb_controller_version` in the tfvars, and the vendored policy file.

## 5. Everything that must be true first

Six prerequisites. Five are Terraform's, one is a chart value. Each fails differently, and two of
them fail in ways that give you no useful error at all.

| # | Prerequisite | Created by | Symptom if missing |
|---|--------------|------------|--------------------|
| 1 | IAM role trusted by `pods.eks.amazonaws.com` | `modules/alb-controller` | pod runs, every AWS call is AccessDenied |
| 2 | The published IAM policy attached to it | `modules/alb-controller` | same, but the log names the missing action |
| 3 | Pod Identity association for the ServiceAccount | `modules/alb-controller` | no credentials reach the pod |
| 4 | `eks-pod-identity-agent` add-on running | `modules/eks` `addons` | association is correct, but nothing delivers the token |
| 5 | `kubernetes.io/role/elb=1` on public subnets | `modules/vpc` | Ingress pending, "unable to discover subnets" |
| 6 | NetworkPolicy admitting the **VPC CIDR** | `values.yaml` `allowFromCIDR` | **silent**: all healthy, targets never pass health checks |

### Why number 6 is the dangerous one

This is the trap created by `target-type: ip`, and it is worth understanding properly because
nothing in any log points at it.

With nginx, traffic reaches your pod **from another pod** in the `ingress-nginx` namespace. A
NetworkPolicy selecting that namespace is exactly right.

With an ALB, traffic reaches your pod **from the load balancer's own network interfaces**, which
live in your VPC subnets. There is no pod and no namespace on the other end. A
`namespaceSelector` therefore matches nothing, and the policy drops:

- every user request, and
- every ALB health check, so the target group shows all targets unhealthy forever

Meanwhile `kubectl get pods` is green, the ALB exists, and the controller logs are clean. So the
charts allow an `ipBlock` of the VPC range on EKS, and a `namespaceSelector` only in the local
overlay:

```yaml
# values.yaml (EKS)          # values-local.yaml (minikube)
networkPolicy:               networkPolicy:
  allowFromCIDR: 10.0.0.0/16   allowFromNamespace: ingress-nginx
  allowFromNamespace: ""       allowFromCIDR: ""
```

**Known sharp edge.** That CIDR is written by hand and must match the environment's VPC. dev is
`10.0.0.0/16` and prod is `10.1.0.0/16`, so a prod app deployment needs its own overlay with the
prod range. Change a VPC CIDR and this must change with it, or the environment goes dark in the
way described above. A tighter version would restrict to the subnet ranges rather than the whole
VPC; the whole VPC is the deliberate simplification here.

### Verify all six

```bash
CLUSTER=pixnest; REGION=ap-south-1
aws iam get-role --role-name pixnest-alb-controller --query 'Role.RoleName'
aws eks list-pod-identity-associations --cluster-name $CLUSTER --region $REGION \
  --query "associations[?serviceAccount=='aws-load-balancer-controller']"
aws eks list-addons --cluster-name $CLUSTER --region $REGION      # expect eks-pod-identity-agent
VPC=$(aws eks describe-cluster --name $CLUSTER --region $REGION \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)
aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC \
  --query 'Subnets[].[SubnetId,Tags[?Key==`kubernetes.io/role/elb`].Value|[0]]' --output text
aws ec2 describe-vpcs --vpc-ids $VPC --query 'Vpcs[0].CidrBlock'   # must equal allowFromCIDR
```

## 6. Verifying it works

```bash
# the controller itself
kubectl -n kube-system get deploy aws-load-balancer-controller
kubectl get ingressclass
kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail=50

# it really is using Pod Identity, not a key
kubectl -n kube-system exec deploy/aws-load-balancer-controller -- env | grep AWS_CONTAINER

# the ALB, once the app is deployed
kubectl -n pixnest get ingress pixnest
aws elbv2 describe-load-balancers --query 'LoadBalancers[].[LoadBalancerName,DNSName,State.Code]' --output text
aws elbv2 describe-target-groups --query 'TargetGroups[].TargetGroupArn' --output text
```

The single most useful check when a page will not load is target health. If the targets are
unhealthy while the pods are Ready, look at prerequisite 6 before anything else:

```bash
for TG in $(aws elbv2 describe-target-groups --query 'TargetGroups[].TargetGroupArn' --output text); do
  aws elbv2 describe-target-health --target-group-arn "$TG" \
    --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]' --output text
done
```

## 7. How the ALB gets deleted, and teardown

### The finalizer, which is the mechanism

Deleting an Ingress does not delete the load balancer directly. It triggers a controlled teardown
through a **finalizer**.

When the controller builds an ALB it adds a finalizer to the Ingress, named after the group, for
example `group.ingress.k8s.aws/argocd`. A finalizer tells Kubernetes: do not actually remove this
object yet. So on a delete, Kubernetes sets `deletionTimestamp` and leaves the object in place.
That pause is what lets the controller clean up AWS *before* the object describing what to clean
up disappears.

The controller then reconciles. It does not handle "delete" as a special case: it recomputes what
AWS should look like for that Ingress group, gets "nothing", and reconciles reality to match. The
same loop that built the load balancer, running backwards. Only when AWS is clean does it release
the finalizer, and only then does the Ingress object vanish.

A real teardown, from the controller's log:

```
06:32:03  successfully built model      <- desired state is now empty
06:32:03  deleting loadBalancer
06:32:04  deleted loadBalancer
06:32:04  deRegistering targets         <- pod IPs out of the target group
06:32:04  deleting targetGroupBinding
06:32:09  deleted targetGroup
06:32:09  deleting securityGroup
06:32:26  deleted securityGroup         <- the ALB's, and the shared backend SG
06:32:26  successfully deployed model
```

Twenty-five seconds. Note the gap at 06:32:19: the first security group delete failed because the
load balancer's network interfaces had not finished detaching. The controller backed off and
retried. Transient errors during teardown are normal, so give it a minute before intervening.

This is also why turning the ALB on and off is safe and repeatable. Flipping
`ingress.enabled: false` and running `helm upgrade` removes the Ingress, and everything above
follows automatically.

### Order matters



The ALB belongs to the **Ingress**, and Terraform does not know it exists. Delete the Ingress
before destroying the infrastructure, or `terraform destroy` fails on the VPC with
`DependencyViolation`, because the load balancer still holds network interfaces in the subnets.

```bash
kubectl delete ingress -A --all                                 # removes the ALB
kubectl delete svc -A --field-selector spec.type=LoadBalancer   # any classic ELB
kubectl -n pixnest delete pvc --all                           # the EBS volumes
```

Uninstalling the controller's Helm release before deleting the Ingress leaves the ALB orphaned,
because the thing that would clean it up is gone - **and worse**, the finalizer is still on the
Ingress with nothing left to release it, so the Ingress can never be deleted either. You then
have to remove the finalizer by hand and delete the load balancer yourself.

Order, always: delete the Ingress, wait for the controller to finish, then remove the controller.

If a destroy is already failing, find the leftovers by hand:

```bash
aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC'].LoadBalancerArn"
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" \
  --query "SecurityGroups[?GroupName!='default'].[GroupId,GroupName]" --output text
```

## 8. Exposing Argo CD through the ALB

Argo CD is the second thing that wants an Ingress, and its chart has three traps that the
application chart does not. Working values are in `infra/platform/argocd/values.yaml`.

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace   --version 10.9.0 -f infra/platform/argocd/values.yaml --wait
```

### Trap 1: `controller: aws` breaks on an HTTP listener

The chart's `server.ingress.controller` accepts `generic` or `aws`. Setting it to `aws` adds a
second route for the Argo CD **CLI**, which speaks gRPC, with a target group whose
protocol-version is `GRPC`. An ALB only supports gRPC target groups behind an **HTTPS** listener.
On an HTTP-only listener the controller fails every reconcile and the Ingress never gets an
address:

```
InvalidLoadBalancerAction: Listener protocol 'HTTP' is not supported
with a target group with the protocol-version 'GRPC'
```

Use `controller: generic` until you have a certificate and an HTTPS listener. The web UI works
fine; only the CLI's gRPC transport is affected, and it falls back to HTTP/1.

### Trap 2: the default hostname

`global.domain` defaults to `argocd.example.com` and becomes the Ingress host. A host rule only
matches requests carrying that `Host` header, so browsing the load balancer's own DNS name
returns 404 while everything looks healthy. Set `global.domain: ""` to render `host: null`, which
matches any host. Set a real hostname once you have DNS.

Note that `server.ingress.hosts: ["*"]` does **not** do this. It is silently ignored in favour of
`global.domain`, and `*` is not a valid Ingress host on its own anyway.

### Trap 3: `scheme: internal`

An internal ALB gets only private IPs and is unreachable from a laptop. The symptom, a name that
resolves but never connects, is indistinguishable from a broken deployment. Use
`internet-facing` unless you are deliberately on a VPN or in the VPC.

### Two more settings that matter

- `configs.params.server.insecure: true`. Otherwise argocd-server serves HTTPS with a
  self-signed certificate, the plain HTTP health check gets a TLS error, and every target stays
  unhealthy. With the ALB as the TLS edge this is the normal arrangement.
- `healthcheck-path: /healthz`. The default `/` redirects, which fails the check.

### Cost: a second load balancer

Argo CD uses `group.name: argocd`, deliberately **not** the application's `pixnest` group.
Sharing a group puts both on one ALB and saves an hourly charge, but Argo CD and the frontend
both serve path `/` with no hostname to distinguish them, so the two rules would collide and
route unpredictably. Separate groups means two ALBs and two charges.

To get back to one load balancer, give each a real hostname and share the group. To pay nothing
at all, skip the Ingress entirely:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80   # then http://localhost:8080
```

### How these values were arrived at

Not by reading the chart's 4,942-line values file. The method - including the render diff that
exposed the gRPC target group in one command - is in
[CONFIGURING-HELM-CHARTS.md](CONFIGURING-HELM-CHARTS.md).

### Verified

These values were applied to the live cluster on 2026-09-12: the Ingress received an address, the
target group came up as `HTTP`/`HTTP1` rather than `GRPC`, targets went healthy, and the UI
returned HTTP 200 with `<title>Argo CD</title>`.

## 9. The TLS upgrade, which is the point of using an ALB

Today the listener is plain HTTP on port 80. The reason to be on an ALB is that HTTPS becomes
configuration rather than a component to operate: request a certificate in ACM, then add three
annotations.

```yaml
albAnnotations:
  alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
  alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-south-1:<account>:certificate/<id>
  alb.ingress.kubernetes.io/ssl-redirect: "443"
```

No cert-manager, no renewal job, no private key in the cluster. ACM renews on its own. The same
load balancer is also where you would attach WAF.

## 10. Status

The controller itself is **proven**: on 2026-09-12 it built a real ALB for Argo CD, registered
pod IPs as targets, passed health checks and served HTTP 200. So prerequisites 1 to 5 are
confirmed working on this cluster.

What is **still unexercised** is the application's own Ingress, and with it prerequisite 6 - the
NetworkPolicy admitting the VPC CIDR. Argo CD did not test that path, because its chart ships a
NetworkPolicy that allows all sources. The application's does not. That remains the most likely
thing to bite on the first full run.

