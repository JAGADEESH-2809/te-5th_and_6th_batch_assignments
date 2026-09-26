# ECR module: one repository per image, with scanning, immutable tags, and untagged cleanup.

resource "aws_ecr_repository" "this" {
  for_each             = toset(var.repositories)
  name                 = each.value
  image_tag_mutability = "IMMUTABLE" # a tag (git SHA) always maps to the same image
  # Allows `terraform destroy` to delete a repository that still holds images. Convenient for
  # a demo environment that is rebuilt constantly; false in prod, where deleting the registry
  # would throw away every deployable artifact.
  force_delete = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after ${var.untagged_expire_days} days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = var.untagged_expire_days
      }
      action = { type = "expire" }
    }]
  })
}
