# argocd - GitOps app-of-apps

Argo CD is the GitOps controller: it watches this repo and continuously syncs the cluster to
match Git (and self-heals drift). With one chart per component, delivery uses the
**app-of-apps** pattern: you apply ONE root Application, and it manages a child Application
per chart, ordered by sync waves (postgres first, then backend, then frontend).

| Path | What |
|------|------|
| `application.yaml` | The **EKS root**: watches `apps/`. Apply this one manifest on the real cluster. |
| `apps/{postgres,backend,frontend}.yaml` | EKS child apps: each points at its chart with `values.yaml` + `values-eks.yaml`, auto-sync + self-heal + prune, sync-waved 0/1/2. |
| `application-local.yaml` | The **minikube root**: watches `apps-local/`. |
| `apps-local/…` | Same children with the `values-local.yaml` overlays (locally built images, MinIO). |

## Apply (once per cluster)
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# Give Argo CD read access to the private repo (a repository credential), then:
kubectl apply -f infra/argocd/application.yaml          # EKS (or application-local.yaml on minikube)
```
From then on, a CI image-tag bump in Git rolls out automatically; adding a chart is just a new
file in `apps/`.
