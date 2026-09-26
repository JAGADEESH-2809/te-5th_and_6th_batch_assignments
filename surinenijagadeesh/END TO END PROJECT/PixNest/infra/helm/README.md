# Helm charts - one per component

Each component ships as its **own chart** (as separate teams would own them in an org),
composed at deploy time by the Argo CD **app-of-apps** in [`../argocd/`](../argocd/):
postgres syncs first, then backend, then frontend (sync waves).

| Chart | What it deploys |
|-------|-----------------|
| [`postgres/`](postgres/) | Hardened single-replica StatefulSet + PVC + Secret + NetworkPolicy. |
| [`backend/`](backend/) | FastAPI Deployment + Service + HPA + ServiceAccount (Pod Identity) + config/secret + NetworkPolicy + PDB. |
| [`frontend/`](frontend/) | nginx SPA Deployment + Service + the app **Ingress** + NetworkPolicy + PDB. |

## Cross-chart conventions (fixed names)
Charts reference each other by stable Service names, not Helm lookups:
- backend Service = `pixnest-backend` (the frontend Ingress routes `/api` there)
- postgres Service = `pixnest-postgres` (the backend's `database.host`)
- backend `database` values must match postgres `auth` values (demo creds; production moves
  both to External Secrets)

## Per-chart value files
`values.yaml` (base, CI bumps image tags) + `values-local.yaml` (minikube) +
`values-eks.yaml` (real cluster). Lint/render any chart standalone:
```bash
helm lint infra/helm/backend
helm template pixnest-backend infra/helm/backend -f infra/helm/backend/values-eks.yaml
```

