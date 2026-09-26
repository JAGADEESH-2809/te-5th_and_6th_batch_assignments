# Chart: pixnest-backend

The FastAPI API: Deployment (hardened, probed, zone-spread), Service (8000), HPA,
ServiceAccount (bound to AWS via Pod Identity), ConfigMap + Secret (DATABASE_URL, JWT_SECRET),
NetworkPolicy (only the ingress controller may reach it), and a PodDisruptionBudget.

Cross-chart conventions (fixed names): this chart's Service is `pixnest-backend`; it reaches
Postgres at `pixnest-postgres` (the postgres chart); the frontend chart's Ingress routes
`/api` here.

| Values file | Use |
|-------------|-----|
| `values.yaml` | Base (CI bumps `image.tag`). |
| `values-local.yaml` | minikube: local image, MinIO via `extraEnv`, one replica. |
| `values-eks.yaml` | EKS: real ECR repo + S3 bucket, production env. |

Secrets: demo defaults render into a chart-managed Secret; production sets `existingSecret`
(External Secrets / AWS Secrets Manager) holding `DATABASE_URL` and `JWT_SECRET`.

