#!/usr/bin/env bash
set -euo pipefail

aws configure --profile bootstrap_github_oidc

read -rp "Enter your 6-digit MFA code: " MFA_CODE

aws sts get-session-token --profile bootstrap_github_oidc \
  --duration-seconds 900 \
  --serial-number arn:aws:iam::242201314218:mfa/iphone-mcilek-aws-mcilek \
  --token-code "${MFA_CODE}" > "${HOME}/github-oidc-session.json"

export AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' "${HOME}/github-oidc-session.json")
export AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' "${HOME}/github-oidc-session.json")
export AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' "${HOME}/github-oidc-session.json")

rm -f "${HOME}/github-oidc-session.json"

echo "AWS temporary credentials set in the environment for 1 hour."


aws sts get-caller-identity --profile bootstrap_github_oidc

aws iam create-open-id-connect-provider --profile bootstrap_github_oidc --url \
  "https://token.actions.githubusercontent.com" --thumbprint-list \
  "6938fd4d98bab03faadb97b34396831e3780aea1" --client-id-list \
  'sts.amazonaws.com'

aws iam create-role --profile bootstrap_github_oidc --role-name pki-prod-role-github-oidc-AssumeRoleWithAction --assume-role-policy-document file://github-oidc-trust-policy.json

unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
