#!/usr/bin/env bash
set -euo pipefail

############################################
# CONFIG
############################################
readonly AWS_ACCOUNT_ID="242201314218"
readonly AWS_PROFILE="default"
readonly GITHUB_OIDC_URL="https://token.actions.githubusercontent.com"

BREAKGLASS_ROLE_NAME="BreakGlassRoleTrustPolicy"
BREAKGLASS_ASSUME_POLICY_NAME="BreakGlassAssumeRolePolicy"
BREAKGLASS_PERMISSIONS_POLICY_NAME="BreakGlassPermissionsPolicy"
GITHUB_TRUST_POLICY_NAME="GithubTrustPolicy"
GITHUB_ASSUME_POLICY_NAME="GithubTrustPolicy"
BREAKGLASS_ROLE_TRUST_POLICY_PATH="breakglass-role-trust-policy.json"
BREAKGLASS_ASSUME_ROLE_POLICY_PATH="breakglass-assume-role-policy.json"
BREAKGLASS_PERMISSIONS_POLICY_PATH="breakglass-permissions-policy.json"
GITHUB_TRUST_POLICY_PATH="github-oidc-provider-trust-policy.json"
GITHUB_ASSUME_POLICY_PATH="github-odic-provider-assume-role.json"
MFA_SERIAL="arn:aws:iam::${AWS_ACCOUNT_ID}:mfa/iphone-mcilek-aws-bootstrap"
STS_DURATION=900


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

main() {

  parse_args "$@"

  local aws_credentials_file_path="${POSITIONAL_ARGS[0]:-}"


  ############################################
  # VALIDATION
  ############################################
  require_file "${aws_credentials_file_path}"
  require_file "$BREAKGLASS_ROLE_TRUST_POLICY_PATH"
  require_file "$BREAKGLASS_ASSUME_ROLE_POLICY_PATH"
  require_file "$BREAKGLASS_PERMISSIONS_POLICY_PATH"

  read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY < <(tail -n +2 "${aws_credentials_file_path}" | head -n1 | tr -d '\r' | tr ',' ' ')
  echo "Access Key ID: $AWS_ACCESS_KEY_ID"
  echo "Secret Access Key: $AWS_SECRET_ACCESS_KEY"  
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

  ############################################
  # MFA → TEMP SESSION
  ############################################
  read -rp "Enter 6-digit MFA code: " MFA_CODE

  SESSION_JSON=$(aws sts get-session-token --duration-seconds "$STS_DURATION" --serial-number "$MFA_SERIAL" --token-code "$MFA_CODE")

  local aws_access_key_id
  local aws_secret_access_key
  local aws_session_token
  local aws_session_token_ttl
  aws_access_key_id=$(jq -r '.Credentials.AccessKeyId' <<< "$SESSION_JSON")
  aws_secret_access_key=$(jq -r '.Credentials.SecretAccessKey' <<< "$SESSION_JSON")
  aws_session_token=$(jq -r '.Credentials.SessionToken' <<< "$SESSION_JSON")
  aws_session_token_ttl=$(jq -r '.Credentials.Expiration' <<< "$SESSION_JSON")
  log "AWS Access Key ID: ${aws_access_key_id}"
  log "AWS Secret Access Key: ${aws_secret_access_key}"
  log "AWS Session Token: ${aws_session_token}"
  log "AWS Session TTL: ${aws_session_token_ttl}"

  export AWS_ACCESS_KEY_ID="${aws_access_key_id}"
  export AWS_SECRET_ACCESS_KEY="${aws_secret_access_key}"
  export AWS_SESSION_TOKEN="${aws_session_token}"

  local aws_username
  aws_username=$(aws sts get-caller-identity --query Arn --output text | awk -F'/' '{print $NF}')
  log "Authenticated as user: ${aws_username}"

  ############################################
  # IAM SETUP (IDEMPOTENT)
  ############################################
  log "Ensuring Role Exists: ${BREAKGLASS_ROLE_NAME}"
  aws iam get-role --role-name "${BREAKGLASS_ROLE_NAME}" >/dev/null 2>&1 \
    || aws iam create-role --role-name "${BREAKGLASS_ROLE_NAME}" --assume-role-policy-document "file://${BREAKGLASS_ROLE_TRUST_POLICY_PATH}"

  log "Updating Trust Policy: ${BREAKGLASS_ROLE_NAME}"
  aws iam update-assume-role-policy --role-name "${BREAKGLASS_ROLE_NAME}" --policy-document "file://${BREAKGLASS_ROLE_TRUST_POLICY_PATH}"

  aws iam get-role --role-name "${GITHUB_TRUST_POLICY_NAME}" >/dev/null 2>&1 \
    || aws iam create-role --role-name "${GITHUB_TRUST_POLICY_NAME}" --assume-role-policy-document "file://${GITHUB_TRUST_POLICY_PATH}"

  log "Updating Trust Policy: ${GITHUB_TRUST_POLICY_NAME}"
  aws iam update-assume-role-policy --role-name "${GITHUB_TRUST_POLICY_NAME}" --policy-document "file://${GITHUB_TRUST_POLICY_PATH}"

  log "Ensuring Permissions Policy Exists: ${BREAKGLASS_PERMISSIONS_POLICY_NAME}"
  aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${BREAKGLASS_PERMISSIONS_POLICY_NAME}" >/dev/null 2>&1 \
    || aws iam create-policy --policy-name "${BREAKGLASS_PERMISSIONS_POLICY_NAME}" --policy-document "file://${BREAKGLASS_PERMISSIONS_POLICY_PATH}"

  log "Ensuring Assume-Role Policy Exists: ${BREAKGLASS_ASSUME_POLICY_NAME}"
  aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${BREAKGLASS_ASSUME_POLICY_NAME}" >/dev/null 2>&1 \
    || aws iam create-policy --policy-name "${BREAKGLASS_ASSUME_POLICY_NAME}" --policy-document "file://${BREAKGLASS_ASSUME_ROLE_POLICY_PATH}"

  log "Ensuring Assume-Role Policy Exists: ${GITHUB_ASSUME_POLICY_NAME}"
  aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${GITHUB_ASSUME_POLICY_NAME}" >/dev/null 2>&1 \
    || aws iam create-policy --policy-name "${GITHUB_ASSUME_POLICY_NAME}" --policy-document "file://${GITHUB_ASSUME_POLICY_PATH}"

  log "Attaching Role Policy (${BREAKGLASS_PERMISSIONS_POLICY_NAME}) to Role (${BREAKGLASS_ROLE_NAME})"
  aws iam attach-role-policy --role-name "${BREAKGLASS_ROLE_NAME}" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${BREAKGLASS_PERMISSIONS_POLICY_NAME}"
  aws iam attach-user-policy --user-name bootstrap --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${BREAKGLASS_ASSUME_POLICY_NAME}"

  ############################################
  # ASSUME BREAKGLASS ROLE
  ############################################

  log "Assuming Role: ${BREAKGLASS_ROLE_NAME}"
  ASSUME_JSON=$(aws sts assume-role --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${BREAKGLASS_ROLE_NAME}" --role-session-name "breakglass-$(date +%s)" --duration-seconds 900)
  aws_access_key_id=$(jq -r '.Credentials.AccessKeyId' <<< "$ASSUME_JSON")
  aws_secret_access_key=$(jq -r '.Credentials.SecretAccessKey' <<< "$ASSUME_JSON")
  aws_session_token=$(jq -r '.Credentials.SessionToken' <<< "$ASSUME_JSON")
  aws_session_token_ttl=$(jq -r '.Credentials.Expiration' <<< "$ASSUME_JSON")
  log "AWS Access Key ID: ${aws_access_key_id}"
  log "AWS Secret Access Key: ${aws_secret_access_key}"
  log "AWS Session Token: ${aws_session_token}"
  log "AWS Session TTL: ${aws_session_token_ttl}"

  export AWS_ACCESS_KEY_ID="${aws_access_key_id}"
  export AWS_SECRET_ACCESS_KEY="${aws_secret_access_key}"
  export AWS_SESSION_TOKEN="${aws_session_token}"

  aws_username=$(aws sts get-caller-identity --query Arn --output text | awk -F'/' '{print $NF}')
  log "Changed to User: ${aws_username}"

  if aws iam list-open-id-connect-providers \
    | jq -e '.OpenIDConnectProviderList[].Arn' \
    | grep -q token.actions.githubusercontent.com; then
    log "OIDC provider already exists, skipping creation"
  else
    log "Creating GitHub Actions OIDC provider"
    aws iam create-open-id-connect-provider \
      --url "${GITHUB_OIDC_URL}" \
      --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
      --client-id-list "sts.amazonaws.com"
  fi


  ############################################
  # CLEANUP HANDLER
  ############################################
  trap 'unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN' EXIT
}

main "$@"