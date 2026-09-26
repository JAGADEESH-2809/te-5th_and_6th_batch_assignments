# Argo CD install values, and how to get into the UI

Two values files. The default is deliberately the boring, free, private one.

| File | What it does | When to use it |
|------|--------------|----------------|
| `values.yaml` | Installs Argo CD with **no Ingress**. Reach the UI with `kubectl port-forward`. | Always. This is the default. |
| `values-alb-ingress.yaml` | Adds a **public ALB** in front of the UI. | Only once TLS is in place. Read its header first. |

## Install

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  --version 10.9.0 -f infra/platform/argocd/values.yaml --wait --timeout 10m
```

Run it from the repository root, since the `-f` path is relative. `--install` means the same
command works for the first install and for every change after it.

---

## Accessing the UI

### The admin password

Generated at install and stored in a secret:

```
kubectl -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode}}'
```

**That form works in every shell**, because `kubectl` does the decoding itself. The
commonly seen `... -o jsonpath='{.data.password}' | base64 -d` only works where a `base64`
utility exists, so it fails in PowerShell and CMD with
`The term 'base64' is not recognized`. On Windows, either use the command above or decode
in PowerShell directly:

```powershell
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}')))
```

Username is `admin`. Note this secret is the **initial** password only. It is not updated if you
change the password through the UI.

### Default: port-forward

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Then open **`http://localhost:8080`**. Leave that terminal running; closing it closes the tunnel.

**Note the port and the scheme, because getting them wrong looks like a broken install.** Both
Service ports forward to the same container port:

```
http   port 80  -> container 8080
https  port 443 -> container 8080
```

and `values.yaml` sets `server.insecure: true`, so that container speaks **plain HTTP**. Forward
`8080:443`, open `https://`, and you get:

```
error: lost connection to pod
... read: connection reset by peer
```

because the client offers TLS and the server answers HTTP. With insecure mode it is **port 80 and
`http://`**. Without it, the reverse: `8080:443` and `https://`, accepting a certificate warning.

### How the port mapping actually works

`kubectl port-forward` is a **tunnel from your own machine**, through the Kubernetes API server,
to a pod. Nothing is exposed on the network, no firewall changes, no cloud resource.

```
your browser          your machine            the cluster
http://localhost:8080  ->  kubectl  ===TLS===>  API server  ->  pod :8080
```

**You always use `localhost`. Never a node IP.** The tunnel only exists inside the `kubectl`
process on your laptop, so `127.0.0.1` is the only address it answers on. A node IP would need a
`NodePort` or `LoadBalancer` Service, and this Service is `ClusterIP`, which by definition has no
address outside the cluster:

```
$ kubectl -n argocd get svc argocd-server -o wide
TYPE        PORT(S)
ClusterIP   80/TCP, 443/TCP        <- no external IP, no node port
```

**The two numbers are `LOCAL:REMOTE`.**

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
#                                                ^^^^ ^^
#                                                |    port ON THE SERVICE
#                                                port on YOUR machine
```

The left number is arbitrary. Pick anything free above 1024; `9090:80` works just as well and you
would then open `http://localhost:9090`. The right number must be a port the Service actually
publishes.

**There are three ports in play, and confusing them is the usual mistake.**

| Layer | Value here | What it is |
|-------|-----------|------------|
| local port | `8080` | your choice, on your laptop |
| Service `port` | `80` and `443` | what the Service publishes inside the cluster |
| Service `targetPort` / container port | `8080` | what the process in the pod listens on |

For this Service both published ports lead to the same place:

```
http   port 80  -> targetPort 8080
https  port 443 -> targetPort 8080
```

That is why choosing 443 does not give you TLS. It is the **same container port** either way, and
with `server.insecure: true` that container speaks plain HTTP. The port number is just a label;
it does not change the protocol. Hence `8080:443` plus `https://` failing with
`connection reset by peer`.

**Forwarding to a Service versus a pod.** `svc/argocd-server` resolves to one of the Service's
pods at connect time, which is what you want: the tunnel survives the pod being replaced only if
you reconnect, but you never have to look up a pod name. `pod/argocd-server-5b9c...` also works
and dies permanently when that pod does.

**Useful variations.**

```bash
# let something other than this machine reach it (careful - this really does expose it)
kubectl -n argocd port-forward --address 0.0.0.0 svc/argocd-server 8080:80

# let the kernel pick a free local port
kubectl -n argocd port-forward svc/argocd-server :80

# forward two ports at once
kubectl -n argocd port-forward svc/argocd-server 8080:80 8443:443
```

**It is a foreground process.** Closing the terminal or pressing Ctrl+C closes the tunnel. It also
drops when the pod restarts, printing `lost connection to pod`, and has to be restarted. That is
normal, not a fault.

### The Argo CD CLI

The CLI talks to the same endpoint, so it works through the same tunnel. With the tunnel running
in another terminal:

```bash
argocd login localhost:8080 --username admin --plaintext \
  --password "$(kubectl -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode}}')"

argocd app list
argocd app get pixnest
argocd app sync pixnest
```

`--plaintext` is needed for the same reason as above: the server is in insecure mode, so the CLI
must not attempt TLS.

The CLI is not installed on this machine and nothing here requires it, since Argo CD syncs from
Git on its own. Install it from the Argo CD releases page if you want it.

### Optional: a public ALB

```bash
helm upgrade --install argocd argo/argo-cd -n argocd --version 10.9.0 \
  -f infra/platform/argocd/values.yaml \
  -f infra/platform/argocd/values-alb-ingress.yaml --wait

kubectl -n argocd get ingress argocd-server    # ADDRESS appears after a minute or two
```

**Read the overlay's header first.** As written it is plain HTTP on a public load balancer, so the
admin password crosses the internet in cleartext, and that account holds cluster-admin plus a
GitHub token with write access to this repo.

## Why no Ingress by default

**Security.** Argo CD's admin is the most privileged identity in the cluster. Putting its login on
a public HTTP endpoint is worse than it sounds: ALB DNS names are not secret, and the login page
is reachable by anyone who finds one.

**Cost.** An ALB is about $0.0225 an hour, roughly $16 a month. Argo CD cannot share the
application's ALB, because both serve path `/` with no hostname to tell them apart, so the overlay
means a second load balancer. Port-forward costs nothing.

## Turning the ALB off again

Set the values back to the default and upgrade. No uninstall, no `kubectl delete`:

```bash
helm upgrade --install argocd argo/argo-cd -n argocd --version 10.9.0 \
  -f infra/platform/argocd/values.yaml --wait
```

`helm upgrade` is declarative. It renders the chart with the new values, compares that against
what the previous revision rendered, and deletes whatever is no longer there. The Ingress goes,
and the AWS Load Balancer Controller then removes the load balancer it built from it.

**The controller does that through a finalizer.** When it created the ALB it added
`group.ingress.k8s.aws/argocd` to the Ingress, which tells Kubernetes not to actually remove the
object until the controller allows it. On deletion the controller sees the pending removal,
recomputes what AWS should look like, gets "nothing", and tears down in dependency order before
releasing the finalizer. From its own log:

```
deleting loadBalancer -> deRegistering targets -> deleting targetGroup
  -> deleting securityGroup -> successfully deployed model
```

Twenty-five seconds, verified 2026-09-13. One security group delete failed on the first attempt
because the load balancer's network interfaces had not finished detaching; the controller retried
and succeeded. Give it a moment before assuming something is wrong.

**Order matters when tearing everything down.** Delete the Ingress and let the controller finish
*before* removing the controller. Uninstall the controller first and the ALB is orphaned, with
nothing left to delete it, and the finalizer then blocks the Ingress from ever being removed.

## Troubleshooting access

| Symptom | Cause | Fix |
|---------|-------|-----|
| `connection reset by peer` on port-forward | forwarding to 443 while `server.insecure: true` | use `8080:80` and `http://` |
| Browser warns about the certificate | forwarding to 443 without insecure mode | expected; accept it, or use port 80 |
| `invalid username or password` | password was changed through the UI | the initial secret is not updated after a change |
| Ingress has no ADDRESS | the controller rejected it | `kubectl -n argocd get events --sort-by=.lastTimestamp \| grep -i fail` |
| ALB exists but the page never loads | targets unhealthy | `aws elbv2 describe-target-health --target-group-arn <arn>` |

Background: [../../../docs/INGRESS-AND-ALB.md](../../../docs/INGRESS-AND-ALB.md) for how an
Ingress becomes a load balancer and the three chart traps, and
[../../../docs/CONFIGURING-HELM-CHARTS.md](../../../docs/CONFIGURING-HELM-CHARTS.md) for how these
values were worked out without reading 4,942 lines.

