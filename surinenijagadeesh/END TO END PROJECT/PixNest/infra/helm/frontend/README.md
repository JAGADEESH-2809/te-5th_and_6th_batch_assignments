# Chart: pixnest-frontend

The React SPA served by nginx-unprivileged: Deployment (hardened, zone-spread), Service (80 ->
8080), NetworkPolicy, PodDisruptionBudget - and the app **Ingress** (this chart owns it because
the frontend is the entry point). The Ingress routes `/` here and `/api` (plus `/docs` when
`exposeDocs`) to the backend chart's fixed Service name (`pixnest-backend`).

| Values file | Use |
|-------------|-----|
| `values.yaml` | Base (CI bumps `image.tag`); ingress annotations include the 10m body-size fix. |
| `values-local.yaml` | minikube: local image, one replica. |
| `values-eks.yaml` | EKS: real ECR repo, Swagger hidden. |

