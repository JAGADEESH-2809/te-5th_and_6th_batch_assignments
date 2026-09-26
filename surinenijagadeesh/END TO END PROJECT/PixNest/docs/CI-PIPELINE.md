# The CI pipeline, explained

What `.github/workflows/ci.yml` does, stage by stage, including what every tool in it is for.

Written to be read start to finish. If you only want the design reasoning, section 9 has it.

---

## 1. The big picture

One sentence: this pipeline tests the code, builds container images, scans them for known
vulnerabilities, pushes them to Amazon ECR, then writes the new image tag into a Helm values file
and commits it, so that Argo CD notices and deploys.

The important part is the last step. **The pipeline never deploys anything.** It has no cluster
credentials and could not reach Kubernetes if it wanted to. It writes to Git and stops. Argo CD,
running inside the cluster, pulls from Git and makes the cluster match. That is what makes this
GitOps rather than a normal deploy script.

The flow end to end:

```
developer pushes to main
  -> work out which components changed
  -> test the backend / build the frontend / validate the charts
  -> build container images
  -> scan the images for vulnerabilities
  -> push to ECR
  -> write the new image tag into Helm values and commit
  -> Argo CD sees the commit and deploys
```

There are two pipelines in this repository, and they are separate on purpose:

| Workflow | Owns | How often | What a mistake costs |
|----------|------|-----------|----------------------|
| `ci.yml` | the application | every commit | one Deployment rolls badly, Argo CD rolls it back |
| `terraform.yml` | the infrastructure | rarely, with approval | a cluster or a VPC can be destroyed |

Section 9 explains why that split matters more than it looks.

---

## 2. When the pipeline runs

Three triggers.

**On a push to main**, but only if certain folders changed. A README edit does not start a build.
The watched folders are `backend/`, `frontend/`, `infra/helm/` and the workflow file itself.

**On a pull request**, same folders. Pull requests run the tests but never build or push images.
That is deliberate: a pull request can come from a fork, and a fork must not be able to write to
your container registry.

**Manually**, from the Actions tab. A manual run rebuilds everything regardless of what changed.
This exists for one specific case: after tearing the environment down, the ECR repositories are
empty, and you need a way to rebuild the images without pretending to change code.

## 3. Two safety settings before any job runs

**Concurrency.** Only one run per branch at a time. On a pull request, pushing a new commit
cancels the older run, which saves time and runner minutes. On main, runs are never cancelled.
That second rule matters: a cancelled run on main could stop between pushing an image and writing
the tag, leaving the registry and the Git repository disagreeing about what should be deployed.

**Permissions.** The workflow starts with read-only access to the repository. Two jobs raise it,
and only as far as they need. The image job gains permission to request an identity token, which
is how it authenticates to AWS. The tag-bump job gains write access to the repository, because it
is the only job that commits. Every other job cannot write anything even if something went wrong
inside it.

---

## 4. Stage one: work out what changed

The first job answers a single question: which parts of the repository were touched in this
change?

It uses an action called `paths-filter`, which compares the changed files against a list of
patterns and reports true or false for each group. Three groups are defined: backend, frontend,
and charts, where charts covers both the Helm charts and the Terraform code.

Every later job reads those answers and decides whether to run.

**Why this exists.** Before it, every run rebuilt and republished both images no matter what had
changed. Editing one line of frontend styling rebuilt the backend, pushed a new backend image,
updated its tag, and caused Argo CD to restart the backend pods for no reason. Every commit
redeployed the whole application.

The job also writes a small table into the run summary page, so when you look at a run and wonder
why a job was skipped, the answer is right there.

---

## 5. Stage two: the quality gates

Three jobs run in parallel, each only if its own part of the repository changed.

### The backend job

This is Python. Four things happen.

**Install uv.** `uv` is a package manager for Python, written in Rust. It does the job that `pip`,
`venv` and `pip-tools` traditionally split between them: resolving dependencies, creating the
virtual environment, and installing packages. It is used here mainly because it is fast, often ten
to a hundred times faster than pip, which matters when every commit pays that cost.

**Install the dependencies** with `uv sync --frozen`. The `--frozen` flag is the interesting part.
It tells uv to install exactly what the lock file says and to fail if the lock file no longer
matches the project file. Without it, uv would quietly resolve a fresh set of versions, and your
build would differ from everyone else's. With it, a stale lock file is an error you find here
rather than a mystery you find in production.

**Lint with ruff.** Ruff is a Python linter and formatter, also written in Rust, replacing what
used to be several separate tools such as flake8, isort and black. The pipeline runs it twice:
once to check for code problems, once to check formatting has not drifted. A formatting failure
stops the build, which sounds strict but removes formatting arguments from code review entirely.

**Run the tests with a coverage gate.** `pytest` runs the test suite. The flag
`--cov-fail-under=80` means the job fails if less than eighty percent of the code is exercised by
tests. Coverage is not a measure of quality, but a floor stops the number sliding quietly
downwards over time.

If any of these fail, nothing is built and nothing is deployed.

### The frontend job

This is JavaScript and TypeScript. Two things happen.

**Install with `npm ci`**, not `npm install`. The difference matters. `npm install` may update the
lock file to satisfy the version ranges in `package.json`. `npm ci` deletes any existing modules,
installs exactly what the lock file pins, and fails outright if the lock file and `package.json`
disagree. It is the command intended for automated environments, and it is both faster and
reproducible.

**Build the production bundle** with `npm run build`. This runs Vite, which compiles TypeScript,
bundles the JavaScript, processes the CSS and writes static files ready to be served. The build is
stricter than the development server, so genuine type errors surface here even though the app
seemed fine locally.

### The infrastructure job

This validates how the application is deployed, without needing any cloud access.

**`helm lint`** checks each chart for structural problems: missing required fields, malformed
YAML, a chart that could not possibly install.

**`helm template`** goes further. It renders the chart into the final Kubernetes YAML, exactly as
it would be applied, without touching a cluster. Crucially, the pipeline renders each chart
against **both** its value files, the local one and the EKS one. A chart can render perfectly with
default values and break with the production values, and this is what catches that.

**`terraform fmt -check`** verifies the Terraform files are formatted canonically. It does not
reformat them, it fails if they are not already correct.

**`terraform validate`** checks the configuration is internally consistent: syntax is valid,
variables referenced actually exist, module inputs match. It runs with the backend disabled, so
it needs no credentials and no state file.

---

## 6. Stage three: build, scan and push the images

This job only runs when the pipeline is on main, at least one of the two applications changed, the
earlier gates did not fail, and the AWS settings exist. It is skipped cleanly, and green, before
any infrastructure has been created, so the repository works from its first commit.

**Authenticate to AWS without any stored secret.** There is no AWS access key anywhere in GitHub.
Instead, GitHub issues a short-lived identity token describing the workflow, and AWS is configured
to trust tokens from this specific repository and exchange them for temporary credentials. The
role it assumes can push to the two ECR repositories and do nothing else. Section 9 returns to
why that narrowness is the point.

**Log in to ECR**, which fetches a short-lived registry password so Docker can push.

**Build the images**, one per application, each only if its source changed. The images are built
into the local Docker daemon rather than pushed straight away. That ordering is deliberate,
because the next step needs an image to inspect but nothing should reach the registry yet.

**Scan with Trivy.** Trivy examines a container image and reports known vulnerabilities in both
the operating system packages and the application dependencies. Three settings turn a report into
a gate:

- restricting it to CRITICAL and HIGH, so it fails on things that matter rather than everything
- ignoring vulnerabilities with no available fix, because failing on something unfixable makes the
  gate impossible to act on and people start ignoring it
- making a finding return a failure exit code, which is what actually stops the pipeline

This is not decoration. It has blocked real problems on this project, including an authentication
bypass in a JWT library, and most recently three critical vulnerabilities in the base image's
system packages. In both cases nothing shipped.

**Push the images**, and only after every scan has passed. Scans for both images run before either
push, so a failure cannot leave one image shipped and the other blocked.

**The tag is the Git commit hash.** Combined with ECR being configured for immutable tags, that
means a tag always refers to exactly one set of bytes and can never be repointed. Any running
container can be traced back to one commit, and a rollback is just naming an older tag.

---

## 7. Stage four: hand over to Argo CD

The final job is small and is the point of the whole design.

It uses `yq`, a command-line tool for editing YAML in place, in the same spirit as `sed` but aware
of YAML structure, so it changes a specific field rather than matching text. Here it sets the
image tag in the Helm values file to the new commit hash.

Then it commits and pushes that change.

That is the entire deployment. Argo CD is watching the repository, notices the new commit, sees
that the desired image tag has changed, and rolls out the new version itself.

Three details in this job are worth knowing.

**It only updates the components that were actually built.** This is a correctness requirement,
not an optimisation. If only the backend was rebuilt but both tags were updated, the frontend
chart would point at an image tag that was never created, and those pods would fail to start with
an image pull error. That exact failure has happened on this project.

**The commit message contains `[skip ci]`.** This bump touches a folder that triggers the
pipeline, so without that marker the pipeline would trigger itself, forever.

**The push retries after rebasing.** Someone else may have pushed to main while this run was in
progress, which would make the push fail. Without the retry, the deploy commit would be lost, the
cluster would keep running the old version, and the pipeline would still report success.

---

## 8. What happens after the pipeline finishes

Nothing in GitHub. The rest happens inside the cluster.

Argo CD polls the repository. When it sees the commit, it compares what Git now describes against
what is actually running, finds the image tag differs, and updates the Deployment. Kubernetes then
performs a rolling update: new pods start, pass their readiness checks, and only then are old pods
removed.

If someone changes something directly in the cluster, Argo CD notices the drift and reverts it,
because Git is the source of truth and the cluster is only a copy of it.

---

## 9. Why the pipeline is built this way

**Only what changed gets rebuilt.** Otherwise every commit restarts the entire application, which
is slow, noisy, and makes it impossible to tell an intentional deployment from an accidental one.

**No long-lived cloud credentials.** The pipeline holds no AWS keys. It proves its identity per
run and receives temporary credentials.

**The application pipeline has almost no permissions.** Its AWS role can perform seven container
registry actions and nothing else. The infrastructure pipeline's role has administrator access,
because it genuinely needs it to build networks and clusters. Keeping the two workflows separate
is what allows those two very different levels of trust. Combine them, and every routine
application build would run with administrator rights over the whole AWS account.

Both roles, their trust policies, the exact permission JSON, and how to create them by hand
in your own account are in [`IAM-ROLES-AND-POLICIES.md`](IAM-ROLES-AND-POLICIES.md).

**Security scanning is a gate, not a report.** A report nobody reads changes nothing.

**The pipeline cannot deploy.** It has no cluster credentials at all. Even a complete compromise
of CI could not change what is running, only what Git says should be running, which is visible,
reviewable and revertible.

**Everything is traceable to one commit.** Image tags are commit hashes, tags are immutable, and
the deployment itself is a commit in the repository's history.

---

## 10. The tools, in one place

| Tool | What it is for |
|------|----------------|
| uv | Python package manager. Resolves and installs dependencies from a lock file, very fast. |
| ruff | Python linter and formatter. Replaces flake8, isort and black with one fast tool. |
| pytest | Python test runner. Used here with a coverage floor. |
| npm ci | Installs Node dependencies exactly as the lock file pins them. Fails if the lock file is out of step. |
| Vite | Frontend build tool. Compiles TypeScript and bundles the app into static files. |
| helm lint | Checks a chart for structural problems. |
| helm template | Renders a chart to final Kubernetes YAML without a cluster, so bad output is caught early. |
| terraform fmt | Checks Terraform formatting is canonical. |
| terraform validate | Checks the configuration is internally consistent. No credentials needed. |
| Docker Buildx | Builds the container images. |
| Trivy | Scans images for known vulnerabilities and fails the build on serious ones. |
| yq | Edits YAML in place, structurally rather than by text matching. |
| paths-filter | Reports which groups of files changed, so jobs can skip. |
| Argo CD | Runs in the cluster, watches Git, and makes the cluster match it. Not part of the pipeline. |

---

## 11. What this pipeline deliberately does not do

**It does not deploy.** That is Argo CD's job, and the separation is the security boundary.

**It does not manage infrastructure.** That is the other workflow.

**It does not create version numbers, tags or changelogs.** Commit hashes are the only version,
which is simple and unambiguous but gives you nothing human-readable to talk about in a release.

**It does not run tests against a live environment.** Unit tests and an image scan only. Nothing
verifies the application actually works once deployed.

**It does not sign the images or record their provenance.** Anyone who can write to the registry
could in principle replace an image. Signing, a software bill of materials, and a cluster policy
that only admits signed images are all planned, and none exist yet.

---

## 12. Where it would go next

**Signing and provenance**, using cosign to sign images, Syft to produce a bill of materials, and
a policy engine in the cluster to refuse anything unsigned.

**Reusable workflows**, once there is a third application. With two, the indirection costs more
than it saves. With three or more, the shared build and push logic should live in one place.

**A staging environment** between the pipeline and production, where promotion moves an existing,
already scanned image forward rather than rebuilding it.

**Layer caching for the container builds**, which currently start from cold on every run.

**Integration tests** that deploy to a temporary environment and exercise the application for
real, closing the gap described in section 11.
