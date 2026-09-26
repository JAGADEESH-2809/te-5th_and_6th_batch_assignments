# Module: github-oidc

Creates the IAM role the app CI assumes via GitHub OIDC to push images to ECR (keyless). The
account-wide GitHub OIDC provider is created once by the bootstrap and read here as a data source.

Note: this account emits immutable-ID OIDC subjects (`repo:login@id/repo@id:...`), so
`github_repo` uses wildcards like `JAGADEESH-2809@*/pixnest@*`.

## Inputs
| Name | Type | Description |
|------|------|-------------|
| `name_prefix` | string | Name prefix (e.g. `pixnest` -> role `pixnest-gha`). Distinct per environment: IAM role names are account-global. |
| `github_repo` | string | OIDC subject pattern for the repo (with `@*` wildcards for the numeric ids). |
| `ecr_repository_arns` | list(string) | ECR ARNs the role may push to. |

## Outputs
| Name | Description |
|------|-------------|
| `role_arn` | The CI role ARN (GitHub repo variable `AWS_GHA_ROLE_ARN`). |


