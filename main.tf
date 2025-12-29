# resource "aws_iam_openid_connect_provider" "github" {
#   url = "https://token.actions.githubusercontent.com"
# 
#   client_id_list = [
#     "sts.amazonaws.com"
#   ]
# 
#   thumbprint_list = [
#     "6938fd4d98bab03faadb97b34396831e3780aea1"
#   ]
# }

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# "Federated": "arn:aws:iam::012345678910:oidc-provider/token.actions.githubusercontent.com"
resource "aws_iam_role" "github_oidc" {
  name = "pki-prod-role-github-oidc-AssumeRoleWithAction"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:maxsportsanalysis/bootstrap-terraform:ref:refs/heads/main"
        }
      }
    }]
  })
  max_session_duration = 3600
}
