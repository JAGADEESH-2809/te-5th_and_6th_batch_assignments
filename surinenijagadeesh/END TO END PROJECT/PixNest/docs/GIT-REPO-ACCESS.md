# Giving Argo CD access to the Git repository

Argo CD's whole job is to read a Git repository and make the cluster match it. If that repository
is private, it needs a credential. Choosing the right one is a security decision, not a formality:
this credential is what lets something decide what runs in your cluster.

Four options, worst to best for production. This project uses the third.

---

## The question that decides everything: is the repo private?

Open the repository on GitHub and look at the badge next to its name, beside the owner and repo
name at the top of the page. It reads **Public** or **Private**.

**If the repository is public, stop here.** Argo CD needs no credential at all. Delete the secret
step entirely and point the Application at the HTTPS URL. For a teaching repository this is often
the right answer, and it removes this whole page.

This one is private, so it needs a credential.

---

## Option 1: a personal token from the gh CLI (do not ship this)

```bash
--from-literal=password="$(gh auth token)"
```

Convenient, and wrong for anything lasting. Four problems:

- **It is a person.** The token belongs to a human account. The audit trail shows them, not the
  system, and the credential dies when they leave or rotate it.
- **Far too much access.** A gh OAuth token typically carries `repo`, `workflow`, `gist` and more,
  across **every** repository that account can reach. Argo CD needs to read exactly one.
- **It is whichever account is active.** `gh auth token` returns the token of the currently
  selected account. On a machine with several, you can easily create a valid-looking secret that
  cannot read the repo, and GitHub answers **404 rather than 403** for a private repo you cannot
  see, so the error looks like a typo.
- **Students may not have it.** `gh` may not be installed, and they may not have a token at all.

Fine for a five-minute demo on your own laptop. Not for anything anyone else depends on.

## Option 2: a fine-grained Personal Access Token

The simplest thing that works with no extra tooling at all. Entirely in the browser.

1. Go to **github.com**, click your avatar, then **Settings**.
2. Bottom of the left sidebar: **Developer settings**.
3. **Personal access tokens**, then **Fine-grained tokens**.
4. **Generate new token**.
5. **Token name:** `argocd-pixnest-read`.
6. **Expiration:** set one. 90 days is reasonable; "no expiration" is not.
7. **Repository access:** choose **Only select repositories**, and pick just this repository.
8. **Permissions**, expand **Repository permissions**, find **Contents**, set it to
   **Read-only**. Leave everything else at "No access".
9. **Generate token**, then copy it. GitHub shows it once.

Then:

```bash
kubectl -n argocd create secret generic pixnest-repo \
  --from-literal=type=git \
  --from-literal=url=https://github.com/OWNER/REPO.git \
  --from-literal=username=OWNER \
  --from-literal=password=github_pat_xxxxxxxx

kubectl -n argocd label secret pixnest-repo \
  argocd.argoproj.io/secret-type=repository --overwrite
```

Note the URL is the **HTTPS** form here, matching the credential type. Still tied to a person and
still expiring, but scoped to one repository and read-only. A reasonable classroom choice when
students each work in their own fork.

## Option 3: a deploy key (what this project uses)

A deploy key is an SSH key attached to **one repository** rather than to a person, and it can be
marked read-only. It is the standard answer for "one system needs to read one repo".

**You need no special tooling.** `ssh-keygen` ships with Windows 10 and 11 (in
`C:\Windows\System32\OpenSSH`), with macOS, and with every Linux distribution. Everything else
is a web browser and `kubectl`.

### Step 1: generate a keypair

No passphrase, because nothing can type one for Argo CD.

**macOS, Linux, Git Bash:**

```bash
ssh-keygen -t ed25519 -C "argocd" -f ./argocd_deploy_key -N ""
```

**Windows PowerShell** (note the quoting, which differs):

```powershell
ssh-keygen -t ed25519 -C "argocd" -f .\argocd_deploy_key -N '""'
```

You now have two files. `argocd_deploy_key` is the **private** half and goes into the cluster.
`argocd_deploy_key.pub` is the **public** half and goes onto GitHub.

### Step 2: add the public key to the repository, in the browser

1. Open the repository on GitHub.
2. Click **Settings** (the repo's own Settings tab, not your account settings).
3. In the left sidebar, click **Deploy keys**.
4. Click **Add deploy key**.
5. **Title:** something that says what it is, for example `argocd-dev (read-only)`.
6. **Key:** paste the entire contents of `argocd_deploy_key.pub`. It is one line starting
   `ssh-ed25519 AAAA...`. Open it in any text editor, or print it:
   - PowerShell: `Get-Content .\argocd_deploy_key.pub`
   - bash: `cat ./argocd_deploy_key.pub`
7. **Leave "Allow write access" UNCHECKED.** This is the whole point. Checked, the key can push
   to your repository.
8. Click **Add key**.

Two things to watch for. Paste the `.pub` file, never the other one: if the text begins
`-----BEGIN OPENSSH PRIVATE KEY-----` you have the wrong file, and you should delete the key
and start again with a fresh pair. And it must be **Deploy keys** under the repository, not
"SSH and GPG keys" under your account, which would attach it to you rather than to the repo.

### Step 3: give the private half to Argo CD

```bash
kubectl -n argocd create secret generic pixnest-repo \
  --from-literal=type=git \
  --from-literal=url=git@github.com:OWNER/REPO.git \
  --from-file=sshPrivateKey=./argocd_deploy_key

kubectl -n argocd label secret pixnest-repo \
  argocd.argoproj.io/secret-type=repository --overwrite
```

On PowerShell the same command needs backticks instead of backslashes for line continuation, or
just put it on one line.

The field name must be `sshPrivateKey`, and the URL must be the **SSH form**, `git@github.com:...`
rather than `https://...`. See below for why.

### Step 4: delete the private key from your machine

It lives in the cluster now.

```bash
rm ./argocd_deploy_key ./argocd_deploy_key.pub          # bash
Remove-Item .\argocd_deploy_key, .\argocd_deploy_key.pub   # PowerShell
```

### If you do have the gh CLI

Step 2 collapses to one command. Everything else is the same.

```bash
gh api repos/OWNER/REPO/keys -X POST \
  -f title="argocd-dev (read-only)" \
  -f key="$(cat ./argocd_deploy_key.pub)" \
  -F read_only=true
```

### The URL must match, exactly

Argo CD pairs a credential with a repository **by URL string**. An SSH credential does not apply
to an `https://` Application, and the failure is not obvious:

```
Failed to load target state: ... failed to list refs:
authentication required: Repository not found.
```

That is what you get when the Application says `https://github.com/OWNER/REPO.git` and the only
credential you hold is for `git@github.com:OWNER/REPO.git`. Every `repoURL` in `infra/argocd/`
therefore uses the SSH form.

### Why this is better

| | personal token | deploy key |
|---|---|---|
| Belongs to | a person | one repository |
| Scope | every repo that account can reach | exactly this repo |
| Write access | usually yes | **no**, when marked read-only |
| Survives someone leaving | no | yes |
| Revoke | rotates everything they use | delete one key |
| Needs the gh CLI | yes | no |

Verified on this repository: the key clones successfully, and a push is refused with
`ERROR: The key you are authenticating with has been marked as read only.` That is the guarantee
worth having. Even if the cluster is compromised, the credential cannot alter your source of truth.

## Option 4: a GitHub App (best at organisation scale)

For many repositories or many clusters, a GitHub App beats deploy keys. It issues **short-lived**
tokens rather than a permanent key, has granular per-repository permissions, belongs to the
organisation rather than a person, and appears in the audit log as itself.

Argo CD supports it directly in the repository secret:

```yaml
stringData:
  type: git
  url: https://github.com/OWNER/REPO.git
  githubAppID: "123456"
  githubAppInstallationID: "7891011"
  githubAppPrivateKey: |
    -----BEGIN RSA PRIVATE KEY-----
    ...
```

The cost is setup: registering an App, installing it on the repositories, and managing its private
key. Worth it for a platform team, overkill for one repository.

---

## Where the secret itself should live

Every option above creates a Kubernetes Secret by hand, which means the credential is **not** in
Git, and rebuilding the cluster means remembering to recreate it. That is the standard chicken and
egg of GitOps: the credential that lets you read Git cannot itself be stored in Git in plaintext.

Three real answers:

- **External Secrets Operator** with AWS Secrets Manager. The credential lives in Secrets Manager,
  and a manifest in Git says "fetch it from there". The pod reaches Secrets Manager with EKS Pod
  Identity, the same mechanism the backend uses for S3.
- **Sealed Secrets.** Encrypt the secret with a cluster key and commit the ciphertext. Only that
  cluster can decrypt it.
- **Terraform.** Put the deploy key in the IaC layer that already runs before the cluster exists.
  It then lands in Terraform state, so the state bucket must be treated as sensitive, which it
  already is.

This project creates it by hand in the bootstrap script and says so. That is honest for a teaching
build and would not be acceptable in production.

## Verifying, whichever option you chose

Creating a secret always succeeds. Whether it authenticates only shows up later:

```bash
# the label is what makes Argo CD notice it at all
kubectl -n argocd get secret pixnest-repo -o jsonpath='{.metadata.labels}'

# which credential type is in there
kubectl -n argocd get secret pixnest-repo \
  -o go-template='{{if .data.sshPrivateKey}}deploy key{{else}}token{{end}}{{"\n"}}'

# the real test
kubectl -n argocd get applications
kubectl -n argocd logs deploy/argocd-repo-server --tail=30 | grep -i "auth\|denied\|not accessible"
```

A healthy result is every Application `Synced`. `Unknown` with `authentication required` means the
credential is missing, wrong, or attached to a URL that does not match.

