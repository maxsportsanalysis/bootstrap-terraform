#!/usr/bin/env bash
set -euo pipefail

############################################
# CONFIG
############################################
readonly AWS_ACCOUNT_ID="242201314218"
readonly AWS_PROFILE="default"
readonly GITHUB_OIDC_URL="https://token.actions.githubusercontent.com"

readonly MFA_SERIAL_NAME="iphone-mcilek-aws-bootstrap"
readonly STS_DURATION=900


GITHUB_ROLE_NAME="GithubActionsTerraformRole"
GITHUB_TRUST_POLICY_PATH="github-oidc-trust-policy.json"
GITHUB_PERMISSIONS_POLICY_NAME="GithubActionsTerraformPermissions"
GITHUB_PERMISSIONS_POLICY_PATH="github-oidc-permissions.json"

log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*"
}
error() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: ERROR: $*" >&2
}
fatal() {
  error "$*"
  exit 1
}

usage() {
  cat << EOF
Usage: $0 [-h|--help]

Options:
  -h, --help        Show this help message and exit
Example:
  sudo $0 <root_block_device> <keyfile_block_device>
EOF
  exit 1
}

parse_args() {
  POSITIONAL_ARGS=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        ;;
      --)
        shift
        break
        ;;
      -*)
        echo "Unknown option: $1"
        usage
        ;;
      *)
        POSITIONAL_ARGS+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#POSITIONAL_ARGS[@]} -ne 1 ]]; then
    error "Exactly two positional arguments required."
    usage
  fi
}

############################################
# HELPERS
############################################
log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
}

require_file() {
  [[ -f "$1" ]] || { echo "Missing file: $1"; exit 1; }
}

load_credentials() {
  local aws_credentials_path="$1"
  read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY < <(tail -n +2 "${aws_credentials_path}" | head -n1 | tr -d '\r' | tr ',' ' ')
  echo "Access Key ID: ${AWS_ACCESS_KEY_ID}"
  echo "Secret Access Key: ${AWS_SECRET_ACCESS_KEY}"  
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
}

update_sts_session_credentials() {
  log "Updating the AWS STS session credentials..."
  local mfa_serial="$1"
  local duration="$2"
  local mfa_code

  read -rp "Enter 6-digit MFA code: " mfa_code
  if [[ ! "${mfa_code}" =~ ^[0-9]{6}$ ]]; then
    fatal "Invalid MFA code format"
  fi

  local session_json
  session_json=$(aws sts get-session-token --duration-seconds "${duration}" --serial-number "${mfa_serial}" --token-code "${mfa_code}")

  local aws_access_key_id
  local aws_secret_access_key
  local aws_session_token
  local aws_session_token_ttl
  aws_access_key_id=$(jq -r '.Credentials.AccessKeyId' <<< "${session_json}")
  aws_secret_access_key=$(jq -r '.Credentials.SecretAccessKey' <<< "${session_json}")
  aws_session_token=$(jq -r '.Credentials.SessionToken' <<< "${session_json}")
  aws_session_token_ttl=$(jq -r '.Credentials.Expiration' <<< "${session_json}")
  log "AWS Access Key ID: ${aws_access_key_id}"
  log "AWS Secret Access Key: ${aws_secret_access_key}"
  log "AWS Session Token: ${aws_session_token}"
  log "AWS Session TTL: ${aws_session_token_ttl}"

  export AWS_ACCESS_KEY_ID="${aws_access_key_id}"
  export AWS_SECRET_ACCESS_KEY="${aws_secret_access_key}"
  export AWS_SESSION_TOKEN="${aws_session_token}"
}

create_role() {
  local role_name="$1"
  local role_policy_document_path="$2"

  log "Creating/Updating IAM role: ${role_name}"

  if aws iam get-role --role-name "${role_name}" >/dev/null 2>&1; then
    log "IAM Role Exists: ${role_name}"
  else
    echo "IAM Role does not exist. Creating role (${role_name}) with permissions from ${role_policy_document_path}"
    aws iam create-role --role-name "${role_name}" --assume-role-policy-document "file://${role_policy_document_path}"
  fi

  log "Updating IAM Role (${role_name}) Policy Document: ${role_policy_document_path}"
  aws iam update-assume-role-policy --role-name "${role_name}" --policy-document "file://${role_policy_document_path}"

  log "Successfully created IAM Role: ${role_name}"
}

create_policy() {
  local policy_arn="$1"
  local policy_name="$2"
  local policy_document_path="$3"
  if aws iam get-policy --policy-arn "${policy_arn}" >/dev/null 2>&1; then
    log "IAM Policy already created: ${policy_name} (${policy_arn})"
  else
    log "Creating IAM Policy: ${policy_name}"
    aws iam create-policy --policy-name "${policy_name}" --policy-document "file://${policy_document_path}"
  fi
}

assume_role() {
  local role_name="$1"
  local role_arn="$2"
  local duration="$3"
  log "Assuming Role: ${role_name} (${role_arn})"

  local assume_role_json
  assume_role_json=$(aws sts assume-role --role-arn "${role_arn}" --role-session-name "${role_name}-$(date +%s)" --duration-seconds "${duration}")
  
  local aws_access_key_id
  local aws_secret_access_key
  local aws_session_token
  local aws_session_token_ttl
  aws_access_key_id=$(jq -r '.Credentials.AccessKeyId' <<< "${assume_role_json}")
  aws_secret_access_key=$(jq -r '.Credentials.SecretAccessKey' <<< "${assume_role_json}")
  aws_session_token=$(jq -r '.Credentials.SessionToken' <<< "${assume_role_json}")
  aws_session_token_ttl=$(jq -r '.Credentials.Expiration' <<< "${assume_role_json}")
  log "AWS Old Access Key ID (${AWS_ACCESS_KEY_ID}) Updated: ${aws_access_key_id}"  
  log "AWS Old Secret Access Key  (${AWS_SECRET_ACCESS_KEY}) Updated: ${aws_secret_access_key}"
  log "AWS Old Session Token  (${AWS_SESSION_TOKEN}) Updated: ${aws_session_token}"
  log "AWS Updated Session Token TTL: ${aws_session_token_ttl}"

  export AWS_ACCESS_KEY_ID="${aws_access_key_id}"
  export AWS_SECRET_ACCESS_KEY="${aws_secret_access_key}"
  export AWS_SESSION_TOKEN="${aws_session_token}"
  log "Changed Identity: $(aws sts get-caller-identity --query Arn --output text | awk -F'/' '{print $NF}')"
}

main() {

  parse_args "$@"

  local aws_credentials_path="${POSITIONAL_ARGS[0]:-}"

  # VALIDATION
  require_file "${aws_credentials_path}"
  require_file "${GITHUB_TRUST_POLICY_PATH}"
  require_file "${GITHUB_PERMISSIONS_POLICY_PATH}"

  load_credentials "${aws_credentials_path}"

  # MFA → TEMP SESSION
  update_sts_session_credentials "arn:aws:iam::${AWS_ACCOUNT_ID}:mfa/${MFA_SERIAL_NAME}" "${STS_DURATION}"
  log "AWS Active Identity: $(aws sts get-caller-identity --query Arn --output text | awk -F'/' '{print $NF}')"

  # IAM SETUP (IDEMPOTENT)
  local github_oidc_policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${GITHUB_PERMISSIONS_POLICY_NAME}"
  create_role "${GITHUB_ROLE_NAME}" "${GITHUB_TRUST_POLICY_PATH}"
  create_policy "${github_oidc_policy_arn}" "${GITHUB_PERMISSIONS_POLICY_NAME}" "${GITHUB_PERMISSIONS_POLICY_PATH}"
  aws iam attach-role-policy --role-name "${GITHUB_ROLE_NAME}" --policy-arn "${github_oidc_policy_arn}"
  
  #aws iam put-role-policy --role-name "${GITHUB_ROLE_NAME}" --policy-name "${GITHUB_PERMISSIONS_POLICY_NAME}" --policy-document "file://${GITHUB_PERMISSIONS_POLICY_PATH}"
  
  aws iam attach-user-policy --user-name bootstrap --policy-arn "${github_oidc_policy_arn}"

  # ASSUME ROLE
  assume_role "${GITHUB_ROLE_NAME}" "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${GITHUB_ROLE_NAME}" "${STS_DURATION}"

  # Verify Policy Creation Permissions
  verify_create_roles_policy_document_path="verify_create_roles_permission.json"
  if aws iam create-role --role-name "__permission_check__" --assume-role-policy-document "file://${verify_create_roles_policy_document_path}" >/dev/null 2>&1; then
    aws iam delete-role --role-name "__permission_check__" >/dev/null 2>&1;
    log "AWS Caller CAN create roles: $(aws sts get-caller-identity --query Arn --output text | awk -F'/' '{print $NF}')"
  else
    log "AWS Caller CANNOT create roles: $(aws sts get-caller-identity --query Arn --output text | awk -F'/' '{print $NF}')"
  fi


  # if aws iam list-open-id-connect-providers \
  #   | jq -e '.OpenIDConnectProviderList[].Arn' \
  #   | grep -q token.actions.githubusercontent.com; then
  #   log "OIDC provider already exists, skipping creation"
  # else
  #   log "Creating GitHub Actions OIDC provider"
  #   aws iam create-open-id-connect-provider \
  #     --url "${GITHUB_OIDC_URL}" \
  #     --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
  #     --client-id-list "sts.amazonaws.com"
  # fi


  ############################################
  # CLEANUP HANDLER
  ############################################
  trap 'unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN' EXIT
}

main "$@"