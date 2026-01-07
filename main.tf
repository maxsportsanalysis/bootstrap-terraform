module "terraform_bucket" {
  source              = "modules/s3_bucket"
  bucket_name         = var.terraform_bucket_name
  versioning_enabled  = var.terraform_bucket_versioning_enabled
  object_lock_enabled = var.terraform_bucket_object_lock_enabled
  object_lock_mode    = var.terraform_bucket_object_lock_mode
  object_lock_retention_days = var.terraform_bucket_object_lock_retention_days
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "github_terraform_role" {
  name = "github-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = [
              "repo:maxsportsanalysis/bootstrap-terraform:ref:refs/heads/main",
              "repo:maxsportsanalysis/infra-terraform:ref:refs/heads/main"
            ]
          }
        }
      }
    ]
  })
}
