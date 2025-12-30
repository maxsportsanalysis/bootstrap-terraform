#!/usr/bin/env bash
set -euo pipefail

aws iam create-user \
  --user-name breakglass-pki-admin

aws iam attach-user-policy \
  --user-name breakglass-pki-admin \
  --policy-arn arn:aws:iam::aws:policy/IAMFullAccess

aws iam create-virtual-mfa-device \
  --virtual-mfa-device-name breakglass-pki-admin-mfa \
  --outfile /tmp/mfa-qr.png \
  --bootstrap-method QRCodePNG

aws iam enable-mfa-device \
  --user-name breakglass-pki-admin \
  --serial-number arn:aws:iam::<ACCOUNT_ID>:mfa/breakglass-pki-admin-mfa \
  --authentication-code1 123456 \
  --authentication-code2 654321

aws sts get-session-token \
  --profile breakglass-pki-admin \
  --serial-number arn:aws:iam::<ACCOUNT_ID>:mfa/breakglass-pki-admin-mfa \
  --token-code 123456 \
  --duration-seconds 900 > /tmp/session.json

export AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' /tmp/session.json)
export AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' /tmp/session.json)
export AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken')

shred -u /tmp/session.json

aws sts get-caller-identity
# Returns: arn:aws:sts::<ACCOUNT_ID>:assumed-role/breakglass-pki-admin/RootCACeremony

aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

aws iam create-role \
  --role-name pki-prod-github-bootstrap \
  --assume-role-policy-document file://github-oidc-trust-policy.json

aws iam attach-role-policy \
  --role-name pki-prod-github-bootstrap \
  --policy-arn arn:aws:iam::aws:policy/IAMReadOnlyAccess

aws iam delete-access-key \
  --user-name breakglass-pki-admin \
  --access-key-id <KEY_ID>
