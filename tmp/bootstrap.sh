#!/usr/bin/env bash
set -euo pipefail

readonly AWS_ACCOUNT_ID="242201314218"
readonly PROFILE_NAME="bootstrap_github_oidc"
readonly BREAKGLASS_IAM_USERNAME="breakglass-pki-admin"
readonly BREAKGLASS_ROLE_TRUST_POLICY_PATH="breakglass-role-trust-policy.json"
BREAKGLASS_ROLE_PERMISSIONS_POLICY_PATH="breakglass-permissions-policy.json"
BREAKGLASS_USER_ASSUME_ROLE_POLICY_PATH="breakglass-assume-role-policy.json"


create_user() {
  local username="$1"
  if ! aws iam get-user --user-name "${username}" --profile "${PROFILE_NAME}" >/dev/null 2>&1; then
    aws iam create-user --user-name "${username}" --profile "${PROFILE_NAME}"
  else
    echo "User ${username} already exists, skipping creation."
  fi
}

create_policy() {
  local policy_name="$1"
  local policy_document_path="$2"
  if ! aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" --profile "${PROFILE_NAME}" >/dev/null 2>&1; then
    aws iam create-policy --profile "${PROFILE_NAME}" --policy-name "${policy_name}" --policy-document "${policy_document_path}"
  else
    echo "Policy ${policy_name} already exists, skipping creation."
  fi
}

create_role() {
  local role_name="$1"
  local policy_document_path="$2"
  if ! aws iam get-role --role-name "${role_name}" --profile "${PROFILE_NAME}" >/dev/null 2>&1; then
    aws iam create-role --profile "${PROFILE_NAME}" --role-name "${role_name}" --assume-role-policy-document "${policy_document_path}"
  else
    echo "Role ${role_name} already exists, updating..."
    aws iam update-assume-role-policy --profile "${PROFILE_NAME}" --role-name "${role_name}" --policy-document "${policy_document_path}"
  fi
}

main() {

  local breakglass_iam_username="${POSITIONAL_ARGS[0]:-breakglass}"
  local breakglass_role_trust_policy_name="${POSITIONAL_ARGS[1]:-BreakGlassRoleTrustPolicy}" 
  local breakglass_role_trust_policy_path="${POSITIONAL_ARGS[2]:-breakglass-role-trust-policy.json}" 
  
  local breakglass_assume_role_policy_name="${POSITIONAL_ARGS[3]:-BreakGlassAssumeRolePolicy}"
  local breakglass_assume_role_policy_path="${POSITIONAL_ARGS[4]:-breakglass-assume-role-policy.json}" 

  local breakglass_permissions_policy_name="${POSITIONAL_ARGS[5]:-BreakGlassPermissionsPolicy}"
  local breakglass_permissions_policy_path="${POSITIONAL_ARGS[6]:-breakglass-permissions-policy.json}" 


  aws configure --profile "${PROFILE_NAME}"

  read -rp "Enter your 6-digit MFA code: " MFA_CODE

  aws sts get-session-token --profile "${PROFILE_NAME}" \
    --duration-seconds 900 \
    --serial-number "arn:aws:iam::${AWS_ACCOUNT_ID}:mfa/iphone-mcilek-aws-bootstrap" \
    --token-code "${MFA_CODE}" > "${HOME}/github-oidc-session.json"

  export AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' "${HOME}/github-oidc-session.json")
  export AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' "${HOME}/github-oidc-session.json")
  export AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' "${HOME}/github-oidc-session.json")

  rm -f "${HOME}/github-oidc-session.json"

  create_user "${breakglass_iam_username}"
  create_role "${breakglass_role_trust_policy_name}" "file://${breakglass_role_trust_policy_path}"
  create_policy "${breakglass_permissions_policy_name}" "file://${breakglass_permissions_policy_path}"
  create_policy "${breakglass_assume_role_policy_name}" "file://${breakglass_assume_role_policy_path}"


  aws iam attach-role-policy --profile "${PROFILE_NAME}" --role-name "${breakglass_role_trust_policy_name}" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${breakglass_permissions_policy_name}"
  aws iam attach-user-policy --profile "${PROFILE_NAME}" --user-name bootstrap --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${breakglass_assume_role_policy_name}"

  aws sts get-caller-identity
  echo "AWS temporary credentials set in the environment for 1 hour."

  ASSUME_ROLE_JSON=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${breakglass_role_trust_policy_name}" \
  --role-session-name "${breakglass_iam_username}"-$(date +%s))

  echo "Assumed Role: ${breakglass_role_trust_policy_name}"

  aws sts get-caller-identity

  echo "Exporting Variables..."

  export AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' <<< "${ASSUME_ROLE_JSON}")
  export AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' <<< "${ASSUME_ROLE_JSON}")
  export AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' <<< "${ASSUME_ROLE_JSON}")

  aws sts get-caller-identity

  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SESSION_TOKEN

}

main "$@"


  # aws iam create-open-id-connect-provider --profile "${PROFILE_NAME}" --url \
  #   "https://token.actions.githubusercontent.com" --thumbprint-list \
  #   "6938fd4d98bab03faadb97b34396831e3780aea1" --client-id-list \
  #   'sts.amazonaws.com'
  # 
  # aws iam create-role --profile "${PROFILE_NAME}" --role-name pki-prod-role-github-oidc-AssumeRoleWithAction --assume-role-policy-document file://github-oidc-trust-policy.json
