terraform-remote-state-bootstrap/
├── README.md
├── main.tf
├── variables.tf
├── outputs.tf
├── iam/
│   ├── iam_policy.tf
│   ├── iam_role.tf
│   └── variables.tf
├── s3/
│   ├── s3_bucket.tf
│   ├── variables.tf
│   └── outputs.tf
├── dynamodb/
│   ├── dynamodb_table.tf
│   ├── variables.tf
│   └── outputs.tf
├── backend.tf        # Optional backend config if needed here
├── terraform.tfvars  # For variable values (gitignored or environment specific)


aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

aws iam list-open-id-connect-providers

aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com


resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
}


resource "aws_s3_bucket" "terraform_state" {
  bucket = "org-terraform-state"
}