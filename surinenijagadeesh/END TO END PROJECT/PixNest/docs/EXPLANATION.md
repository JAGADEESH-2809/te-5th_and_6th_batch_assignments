# pixnest - Explained (the complete walkthrough)

A plain-language explanation of the whole system: what each piece is, how it is wired, and why
each choice was made. Pair it with [PLAN.md](PLAN.md), the reference architecture.

---

## 1. What pixnest is, in one minute

pixnest is a photo gallery web app. A user uploads photos and sees them in a gallery. The
focus of this project is not the app - it is everything around it: how it is containerized,
deployed to Kubernetes, delivered by GitOps, and wired to the cloud securely and automatically.
The app is deliberately small so the platform stays the interesting part.

**The rule it follows:** files go in object storage (S3); facts about the files go in a
database (Postgres). A 5 MB image does not belong in a database row; a filename and size do.

---

## 2. The big picture: two flows

There are two separate journeys to understand. Keep them apart in your head.

- **Runtime flow** - how a user's request travels: browser -> Ingress -> frontend/backend ->
  S3 + Postgres.
- **Delivery flow** - how your code becomes a running deployment: git push -> CI builds and
  pushes images -> CI writes the new image tag into Git -> Argo CD syncs the cluster to Git.

Everything below is one of these two flows, plus the plumbing that supports them.

---

## 3. Repo tour (what lives where, and why)

In a real company these three boundaries are usually separate repositories. Here they are
top-level folders so the whole project stays in one place.

| Folder | What it is |
|--------|------------|
| `backend/` | The FastAPI app: upload/list/delete photos, plus health/ready/version and Swagger. Async SQLAlchemy 2 + asyncpg for Postgres, boto3 for S3. Tests mock S3 (moto) and use SQLite, so CI needs no cloud. |
| `frontend/` | The React app (Vite + TypeScript + Tailwind + TanStack Query): an upload area and a gallery grid. Built to static files, served by nginx. |
| `infra/terraform/` | The cloud resources as code: ECR registries, the S3 bucket, the GitHub OIDC role, and (when a cluster exists) the backend role + Pod Identity. Runs through a pipeline. |
| `infra/helm/` | Three Kubernetes charts, one per component: `postgres/`, `backend/`, and `frontend/` (which owns the Ingress). Each has base + local + eks value files; the Argo CD app-of-apps composes them at deploy time. |
| `infra/argocd/` | The Argo CD Application manifests that tell Argo which repo/path/chart to watch and where to deploy. |
| `infra/local/` | A minikube run: MinIO (a local stand-in for S3) plus a runbook. |
| `.github/workflows/` | Two pipelines: `ci.yml` (test + build images + GitOps bump) and `terraform.yml` (plan/apply the infra). |
| `docs/` | This file and the reference architecture. |
| `docker-compose.yml` | Local dev: backend + Postgres + MinIO in one command. |

---

## 4. Runtime flow: what happens when you use the app

**On upload (`POST /api/photos`):**
1. The browser sends the image to the API (same origin, under `/api`).
2. The Ingress routes `/api` to the backend Service.
3. The backend validates the file (must be an image, under 10 MB), writes the bytes to S3, and
   inserts one row in Postgres (id, filename, size, content type, the S3 key, the time).
4. It returns the new photo with a short-lived **presigned URL** so the browser can fetch the
   image directly from S3.

**On gallery (`GET /api/photos`):**
1. The backend validates the bearer token and takes the username out of it.
2. It reads that user's rows from Postgres (fast - it is an index of small records).
3. For each row it generates a presigned S3 URL.
4. The browser renders the images by loading those URLs straight from S3.

Step 1 matters more than it looks. Whose photos come back is decided by the token and
nothing else. There is no owner parameter in the request, because a parameter is supplied
by the client and could simply be changed to another user's name.

So the database is queried, but the heavy image bytes travel browser <-> S3 directly. That is
the golden rule in action.

**Why same-origin matters:** the frontend calls `/api` on the same host, so there is no CORS to
configure. Locally that is done with the Vite dev proxy; in the cluster the Ingress does it.

---

## 5. Delivery flow: how a change ships (CI/CD + GitOps)

This is the heart of the project. It is **pull-based GitOps**, not a push pipeline.

1. You push code to `main` (or merge a PR). Branch protection means a red pipeline blocks the merge.
2. **CI (`ci.yml`)** runs: lint (ruff) and tests (pytest) for the backend, a build for the
   frontend, and a lint of the chart and Terraform. On `main`, it then builds both Docker images
   and pushes them to ECR, tagged with the git commit SHA.
3. **CI's job ends in Git:** it writes the new image tags into the backend and frontend charts' `values.yaml`
   and commits that change. It never touches the cluster.
4. **Argo CD**, running inside the cluster, watches this repo. It notices the values changed and
   **syncs** the cluster to match Git - pulling the new images. It also **self-heals**: if
   someone edits the cluster by hand, Argo reverts it back to what Git says.

Why this is good: Git is the single source of truth and the audit log; rollback is `git revert`;
and the cluster's credentials never live in CI (CI only pushes to Git and ECR).

The single most powerful demo in the whole course: break a test, open a PR, watch CI go red and
block the merge; fix it, merge, and watch Argo CD deploy it. That is the entire DevOps promise in
five minutes.

---

## 6. Authentication: keyless everywhere (the part interviewers love)

There are no long-lived AWS keys anywhere in this system. Two different mechanisms make that true:

- **GitHub Actions -> AWS (CI and Terraform): GitHub OIDC.** GitHub mints a short-lived identity
  token for each workflow run; AWS trusts that token (via an IAM OIDC provider) and lets the
  workflow assume a role. So CI can push to ECR and Terraform can manage infra with no stored
  secrets - just a role ARN.
- **Pod -> AWS (backend reads/writes S3): EKS Pod Identity.** The backend Pod's ServiceAccount is
  bound to an IAM role by a Pod Identity association. The role trusts the EKS service principal
  (`pods.eks.amazonaws.com`). No keys in the pod, and no per-cluster OIDC setup.

Pod Identity is the modern successor to **IRSA** (the older 2019 approach, which annotated the
ServiceAccount with a role ARN and relied on a per-cluster OIDC provider). Pod Identity is
simpler and the role is reusable across clusters. IRSA is still widespread, so both are worth
knowing.

One real gotcha we hit and fixed: this GitHub account emits an **immutable-ID subject claim**
(`repo:owner@id/repo@id:...`), so the IAM trust policies use `repo:JAGADEESH-2809@*/pixnest@*:*`
rather than the plain `repo:owner/repo:*`. If a trust policy looks perfect but STS says
"Not authorized", check the actual `sub` claim.

---

## 7. The data stores, and why each

- **S3** for the image files: cheap, effectively unlimited, built for large objects, and it
  serves images directly to browsers via presigned URLs. The bucket is private; nothing is public.
- **Postgres** for metadata: a relational database is the right tool to list, filter, and later
  search records. It runs **in the cluster as a StatefulSet with a PersistentVolumeClaim** - the
  same in local and in EKS.

A StatefulSet (not a Deployment) because a database has state: it needs stable identity and
persistent storage that survives a pod restart. The PVC is the persistent disk; on EKS it is an
EBS volume, which pins the pod to one Availability Zone.

The honest trade-off: running a database inside Kubernetes means you own backups, failover, and
upgrades. A production deployment would use a database operator (CloudNativePG) or a managed
service (RDS/Aurora). It runs in-cluster here to keep the whole stack self-contained and
portable across environments.

---

## 8. Key decisions and the "why"

| Decision | Why |
|----------|-----|
| Python/FastAPI backend | Small and readable, so the interesting complexity stays in the platform. The pipeline is language-agnostic - it would ship a Java or Node app the same way. |
| Postgres as a StatefulSet | Keeps the stack self-contained (stable identity, PVC, persistence). RDS/CloudNativePG is the production path. |
| EKS Pod Identity (not IRSA) | The current, simpler, reusable-across-clusters way for a pod to get an AWS identity. |
| ALB on EKS, nginx locally | The AWS Load Balancer Controller turns the Ingress into a real Application Load Balancer: TLS at the edge with ACM, WAF attachable, and `target-type: ip` routes straight to pod IPs with no node-port hop. minikube has no such controller, so the local overlay switches the class back to nginx - one value, and the template then selects the matching annotations and NetworkPolicy source. |
| GitOps with Argo CD | Git is the source of truth; the cluster self-heals; rollback is a git revert. |
| Keyless OIDC for CI and Terraform | No long-lived secrets to leak or rotate. |
| Remote Terraform state in S3 | Shared, locked, durable state - never on a laptop. |
| Images tagged by git SHA | The exact bytes that passed CI are what run; fully traceable. |

---

## 9. How to run and demo it

- **Just the API (fastest):** `docker compose up` -> open http://localhost:8000/docs and upload a
  photo. Backend + Postgres + MinIO, one command.
- **The full app on real Kubernetes (local):** follow [../infra/local/README.md](../infra/local/README.md).
  minikube + the Helm chart + Argo CD, with a real Ingress and the Postgres StatefulSet. This
  proves the same chart that targets EKS runs locally.
- **The CI/GitOps demo:** break a test in a PR (watch CI block the merge), fix it, merge, and watch
  Argo CD roll it out.

---

## 10. What is built versus what is next

**Built and verified:** the backend and frontend; one Helm chart per component (backend, frontend,
Postgres StatefulSet) composed by the Argo CD app-of-apps; Terraform as reusable modules (VPC, EKS,
ECR, S3, OIDC roles, Pod Identity) with dev and prod environments; the CI and Terraform pipelines
(both green, both keyless); Argo CD GitOps. Verified end to end locally three ways (docker compose,
minikube + Helm, minikube + Argo CD). The full AWS environment has been built and destroyed through
the Terraform pipeline in account 359367063384; the dev environment is torn down between demos to
stop the spend.

**Not yet:** the app has not been exercised end to end on EKS itself (upload through the ingress,
Pod Identity to S3). The first full run is the live class build in
the instructor-only demo runbook; the operational steps are in
[../infra/EKS-DEPLOY.md](../infra/EKS-DEPLOY.md).

**Later phases (additive, no rework):** async worker + SQS + KEDA (thumbnails, scale to zero);
AI with pgvector + Bedrock (semantic photo search); supply-chain security (cosign, SBOM, Kyverno);
observability (OpenTelemetry, Prometheus, Grafana, SLOs); progressive delivery (Argo Rollouts canary).


