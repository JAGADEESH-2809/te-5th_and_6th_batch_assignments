# Configuring a third-party Helm chart without reading it

The Argo CD chart's `values.yaml` is 4,942 lines. Nobody reads that. This is the method for
getting from "I need to install this" to a small, correct values file, using the chart itself to
answer your questions.

The worked example throughout is the failure in
[INGRESS-AND-ALB.md](INGRESS-AND-ALB.md) section 8, where one wrong setting stopped an ALB from
ever being created.

---

## The principle

**You are not writing a values file. You are overriding a handful of defaults.** Everything you
do not write is already set. So the job is to find the three or four keys that matter, and prove
what they do before you install anything.

Two things make this tractable:

- `helm template` renders the final YAML **without touching your cluster**, so you can inspect
  and diff it freely.
- The chart's own comments are usually the best documentation that exists.

## Step 1: see the shape, not the content

```bash
helm show values argo/argo-cd --version 10.9.0 | grep -E "^[a-zA-Z]" | sed 's/:.*//'
```

```
nameOverride  fullnameOverride  global  configs  controller  dex  redis
server  repoServer  applicationSet  notifications  ...
```

Twenty-three top-level keys instead of five thousand lines. Now you know Argo CD is really six or
seven components, and the one serving the web UI is `server`. Everything else is noise for your
purpose.

## Step 2: read the chart's README, not its values

```bash
helm show readme argo/argo-cd --version 10.9.0
```

Chart authors put the intended recipes here. The Argo CD README has an entire "Ingress
configuration" section. Five minutes here saves an hour of guessing.

## Step 3: grep the values file with its comments

The comments are the documentation. Pull just the section you need:

```bash
helm show values argo/argo-cd --version 10.9.0 | grep -n -A30 "^  ingress:"
```

```yaml
ingress:
  # -- Enable an ingress resource for the Argo CD server
  enabled: false
  # -- Specific implementation for ingress controller. One of `generic`, `aws` or `gke`
  controller: generic
  # -- Defines which ingress controller will implement the resource
  ingressClassName: ""
```

Read those two comments carefully, because they are the whole trap. `ingressClassName` "defines
which ingress controller will implement the resource" - that is the real Kubernetes field.
`controller` is a chart-only template switch. Two similarly named fields, completely different
jobs.

## Step 4: start with the smallest thing that could work

Write five lines, not fifty. Add settings only when something forces you to.

```yaml
server:
  ingress:
    enabled: true
    ingressClassName: alb
```

## Step 5: render it and read what you would actually get

```bash
helm template argocd argo/argo-cd --version 10.9.0 -f my-values.yaml > out.yaml
```

Then look at only the object you care about:

```bash
helm template argocd argo/argo-cd --version 10.9.0 -f my-values.yaml \
  | yq 'select(.kind == "Ingress")'
```

No `yq` installed? Python does it:

```bash
helm template argocd argo/argo-cd --version 10.9.0 -f my-values.yaml | python -c "
import sys,yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d.get('kind')=='Ingress': print(yaml.safe_dump(d,sort_keys=False))
"
```

This is where you catch things like "the host is `argocd.example.com` and I never asked for that".

## Step 6: diff two renders to learn what a setting does

**This is the highest-value technique on this page**, and it is how the ALB bug was found. If you
cannot tell what a flag does, set it both ways and compare the output.

```bash
printf 'server:\n  ingress:\n    enabled: true\n    controller: generic\n' > a.yaml
printf 'server:\n  ingress:\n    enabled: true\n    controller: aws\n'     > b.yaml

helm template x argo/argo-cd --version 10.9.0 -f a.yaml > out-generic.yaml
helm template x argo/argo-cd --version 10.9.0 -f b.yaml > out-aws.yaml
diff out-generic.yaml out-aws.yaml
```

The answer came back immediately: `aws` adds a second Service carrying

```yaml
alb.ingress.kubernetes.io/backend-protocol-version: GRPC
```

which is precisely what the ALB refused, because gRPC target groups need an HTTPS listener. No
documentation reading required. The chart told on itself.

The same trick answers "does this flag do anything at all?" If the diff is empty, it does not.

## Step 7: validate against the real API before installing

`helm template` catches template errors. It does **not** catch "the API server will reject this".
A server-side dry run does, and changes nothing:

```bash
helm template argocd argo/argo-cd --version 10.9.0 -f my-values.yaml \
  | kubectl apply -n argocd --server-side --dry-run=server -f -
```

This catches invalid field values, bad hostnames, and admission-webhook rejections.

## Step 8: install, then look where the errors actually appear

This is the step people miss, and it is why the ALB failure was confusing. **Helm reported
success.** The chart was valid, Kubernetes accepted every object, and the pods ran. AWS rejected
the request asynchronously, so the error existed only as Kubernetes events:

```bash
kubectl -n argocd get events --sort-by=.lastTimestamp | grep -i fail
kubectl -n argocd describe ingress argocd-server | tail -20
kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail=50
```

**Rule of thumb: `helm install` succeeding means the manifests were accepted, nothing more.**
Anything a controller does afterwards fails in events and controller logs, never in Helm's output.

## Step 9: check what you have actually set

Over time a values file accumulates settings nobody remembers adding. This shows only your
overrides, not the thousands of defaults:

```bash
helm get values argocd -n argocd
```

To see everything including defaults, `helm get values argocd -n argocd --all`. To see the
rendered manifests of the live release, `helm get manifest argocd -n argocd`.

## Step 10: pin the version, and write down why each line exists

```bash
helm upgrade --install argocd argo/argo-cd -n argocd --version 10.9.0 -f values.yaml
```

Without `--version` you get whatever is newest today, and a teammate installing next month gets
something different. Pin it.

Then comment every non-obvious line with the failure it prevents. Compare:

```yaml
controller: generic          # useless in six months
```

```yaml
# MUST be "generic", not "aws". controller: aws adds a gRPC target group, and an ALB only
# supports those behind an HTTPS listener, so on HTTP every reconcile fails with
# InvalidLoadBalancerAction and the Ingress never gets an address.
controller: generic
```

The second one stops the next person, including you, from "cleaning up" a line that is load
bearing. `infra/platform/argocd/values.yaml` is written this way throughout.

## The loop, condensed

```
shape -> readme -> grep the section -> smallest values -> render -> diff to learn
      -> server dry-run -> install -> READ EVENTS -> pin and comment
```

## Cheat sheet

| Question | Command |
|----------|---------|
| What can I configure? | `helm show values <chart> \| grep -E "^[a-zA-Z]"` |
| How is it meant to be used? | `helm show readme <chart>` |
| What does this section offer? | `helm show values <chart> \| grep -A30 "^  ingress:"` |
| What would I get? | `helm template x <chart> -f v.yaml` |
| What does this flag change? | render twice, `diff` |
| Will the API accept it? | `... \| kubectl apply --server-side --dry-run=server -f -` |
| Why did it not work? | `kubectl get events --sort-by=.lastTimestamp`, controller logs |
| What did I set? | `helm get values <release> -n <ns>` |
| What versions exist? | `helm search repo <chart> --versions` |
