# pixnest

> A full-stack **photo gallery** on Amazon EKS - React + FastAPI + Postgres + **S3 (via EKS Pod Identity)** + an async **thumbnail worker** - delivered by **GitOps (ArgoCD)**. Built to be extended with AI, KEDA, supply-chain security, and full observability.

**Status:** Phase 1 built. Full walkthrough: **[docs/EXPLANATION.md](docs/EXPLANATION.md)**. Reference design: **[docs/PLAN.md](docs/PLAN.md)**.

## Repo layout

| Path | What |
|------|------|
| `backend/` | FastAPI API (S3 + Postgres), tests, Dockerfile |
| `frontend/` | React + TS + Vite + Tailwind + TanStack Query, Dockerfile |
| `infra/` | everything ops: `terraform/`, `helm/` (a chart per component), `argocd/` (app-of-apps), `local/` |
| `docs/` | EXPLANATION.md (walkthrough) + PLAN.md (architecture) |
| `.github/workflows/ci.yml` | test, build+push images (OIDC), GitOps tag bump |
| `docker-compose.yml` | local dev: backend + Postgres + MinIO |

In an organization these three boundaries (`backend`, `frontend`, `infra`) are usually separate
repositories; here they are top-level folders so the whole project stays in one place.

## Quickstart

```bash
# Backend tests (no cloud needed)
cd backend && uv sync && uv run ruff check . && uv run pytest -q

# Full backend stack locally (needs Docker)
docker compose up --build          # Swagger at http://localhost:8000/docs

# Frontend dev (talks to the backend via the Vite proxy)
cd frontend && npm install && npm run dev
```

Deploy: the `terraform` pipeline builds the AWS environment (VPC, EKS, ECR, S3, roles), `infra/scripts/bootstrap-cluster.sh` installs ingress-nginx + Argo CD and applies the app-of-apps root, and Argo CD takes over from there - see `infra/EKS-DEPLOY.md`. Local run: see `infra/local/README.md`.

## Architecture (short)

- **Services (Phase 1):** `frontend` (React/nginx) + `backend` (FastAPI) - on EKS
- **Data:** **S3** for images (via EKS Pod Identity) + **Postgres** for metadata (in-cluster StatefulSet)
- **Delivery:** **Argo CD** watches this repo and syncs the cluster (GitOps); CI builds+pushes images and bumps their tags in Git
- **Rule:** files in S3, metadata in the DB
- An async **worker** (SQS + thumbnails) is **Phase 2** - kept out of Phase 1 to stay beginner-friendly.

## Build phases

1. **Base app + GitOps** (done) - frontend + backend + Postgres + S3, Docker, Terraform, Helm, CI, Argo CD
2. **Async worker + thumbnails** - SQS + worker + **KEDA** (event-driven scaling)
3. **AI** - pgvector semantic search + auto-tagging (AWS Bedrock)
4. **Supply chain** - cosign signing + SBOM + Kyverno policy
5. **Observability** - OpenTelemetry + Prometheus/Grafana + SLOs
6. **Progressive delivery** - Argo Rollouts (canary)

See [docs/PLAN.md](docs/PLAN.md) for the architecture, DB schema, GitOps flow, infra, Helm layout, and the concept map.

