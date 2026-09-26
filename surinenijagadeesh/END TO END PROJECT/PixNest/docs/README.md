# docs - the written material

Read in this order if you are new.

| File | What it is | Use it to |
|------|------------|-----------|
| [`EXPLANATION.md`](EXPLANATION.md) | A complete plain-language walkthrough of the whole system: the two flows, a repo tour, how auth works, the key decisions and why. | Understand and explain *what everything is and why*. |
| [`PLAN.md`](PLAN.md) | The reference architecture: stack table, diagrams, DB schema, GitOps flow, the phased roadmap. | Look up the design and the diagrams. |
| [`PLATFORM-INSTALL.md`](PLATFORM-INSTALL.md) | The platform layer installed by hand, one command at a time, with the teaching point behind each step. The manual equivalent of `bootstrap-cluster.sh`. | Teach the cluster build live, or understand what the script does. |
| [`CI-PIPELINE.md`](CI-PIPELINE.md) | The application pipeline explained stage by stage, including what every tool in it does (uv, ruff, npm ci, helm template, Trivy, yq) and why each gate exists. | Learn or teach how the pipeline works, or change it. |
| [`IAM-ROLES-AND-POLICIES.md`](IAM-ROLES-AND-POLICIES.md) | Every AWS identity the project uses: the two CI/CD roles and the three in-cluster Pod Identity roles, with the actual trust and permission JSON, the console steps to create them by hand, and the OIDC subject-claim trap. | Rebuild the project in your own AWS account, or debug a role that will not assume. |
| [`GIT-REPO-ACCESS.md`](GIT-REPO-ACCESS.md) | How Argo CD authenticates to the Git repository: deploy keys, fine-grained tokens, GitHub Apps, why a personal token is the wrong answer, and where the secret itself should live. | Set up or debug the repository credential. |
| [`CONFIGURING-HELM-CHARTS.md`](CONFIGURING-HELM-CHARTS.md) | How to configure any third-party chart without reading its values file: see the shape, diff two renders to learn what a flag does, validate before installing, and read events rather than Helm output when it fails. | Install a chart you have never used, or work out why one silently did the wrong thing. |
| [`INGRESS-AND-ALB.md`](INGRESS-AND-ALB.md) | How outside traffic reaches a pod: why the AWS Load Balancer Controller rather than nginx, what it builds, the six prerequisites and how each one fails, teardown order, and the TLS upgrade. | Debug an Ingress that will not serve, or explain the request path. |

For running it, see the folder READMEs under [`../infra/`](../infra/) and the root
[`../README.md`](../README.md). The operational runbooks live next to the code they drive:

| Runbook | Covers |
|---------|--------|
| [`../infra/EKS-DEPLOY.md`](../infra/EKS-DEPLOY.md) | Empty AWS account to running app, and the teardown order. |
| [`../infra/CLUSTER-ACCESS.md`](../infra/CLUSTER-ACCESS.md) | Granting, verifying and revoking kubectl access. |

Some material is **instructor-only** and deliberately not committed (see `.gitignore`):
`TEACHING-GUIDE.md`, `PRODUCTION-READINESS.md` and `infra/DEMO-RUNBOOK.md`. They exist on the
instructor's machine only, which is why nothing here links to them.
