# Module: ecr

Creates one Amazon ECR repository per image, with image scanning on push, immutable tags
(a git SHA always maps to the same image), and a lifecycle policy that expires untagged images.

## Inputs
| Name | Type | Description |
|------|------|-------------|
| `repositories` | list(string) | Repository names to create (e.g. `["pixnest-backend","pixnest-frontend"]`). |
| `untagged_expire_days` | number | Days before untagged images are expired. |
| `force_delete` | bool | Let `terraform destroy` delete a repository that still holds images. Dev only - in prod this would throw away every deployable artifact. |

## Outputs
| Name | Description |
|------|-------------|
| `repository_urls` | Map of name -> repository URL (put in Helm image repositories). |
| `repository_arns` | List of repository ARNs (used to scope the CI push policy). |

