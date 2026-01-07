#!/usr/bin/env bash
set -euo pipefail

USER="bootstrap"
ROLE_NAME="Bootstrap"

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
  sudo $0
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

  if [[ ${#POSITIONAL_ARGS[@]} -ne 0 ]]; then
    error "Exactly zero positional arguments required."
    usage
  fi
}

cleanup_user() {
  local user_name="$1"
  # Check if user exists
  if ! aws iam get-user --user-name "${user_name}" > /dev/null 2>&1; then
    log "User ${user_name} does not exist, skipping user cleanup"
  else
    log "Cleaning up access keys for user ${user_name}..."
    local keys
    keys=$(aws iam list-access-keys --user-name "${user_name}" --query 'AccessKeyMetadata[].AccessKeyId' --output text || echo "")

    if [ -n "${keys}" ]; then
      for key in ${keys}; do
        log "Deactivating key ${key}"
        aws iam update-access-key --user-name "${user_name}" --access-key-id "${key}" --status Inactive
        log "Deleting key ${key}"
        aws iam delete-access-key --user-name "${user_name}" --access-key-id "${key}"
      done
    else
      log "No access keys found for user ${user_name}"
    fi

    log "Deleting user inline policies for ${user_name}..."
    local user_policies
    user_policies=$(aws iam list-user-policies --user-name "${user_name}" --query 'PolicyNames' --output text || echo "")
    if [ -n "${user_policies}" ]; then
      for user_policy_name in ${user_policies}; do
        log "Deleting user policy ${user_policy_name} from user ${user_name}"
        aws iam delete-user-policy --user-name "${user_name}" --policy-name "${user_policy_name}"
      done
    else
      log "No user inline policies found for user ${user_name}"
    fi

    log "Deactivating and deleting MFA devices for user ${user_name}..."
    local mfa_devices
    mfa_devices=$(aws iam list-mfa-devices --user-name "${user_name}" --query 'MFADevices[].SerialNumber' --output text || echo "")
    if [ -n "${mfa_devices}" ]; then
      for mfa in ${mfa_devices}; do
        log "Deactivating MFA device ${mfa}"
        aws iam deactivate-mfa-device --user-name "${user_name}" --serial-number "${mfa}"
        log "Deleting virtual MFA device ${mfa}"
        aws iam delete-virtual-mfa-device --serial-number "${mfa}"
      done
    else
      log "No MFA devices found for user ${user_name}"
    fi
  fi
}

cleanup_role() {
  local role_name="$1"

  if aws iam get-role --role-name "${role_name}" > /dev/null 2>&1; then
    log "Cleaning up role ${role_name}..."

    # Detach managed policies
    local policies
    policies=$(aws iam list-attached-role-policies --role-name "${role_name}" --query 'AttachedPolicies[].PolicyArn' --output text || echo "")
    if [ -n "${policies}" ]; then
      for policy_arn in ${policies}; do
        echo "Detaching managed policy ${policy_arn} from role ${role_name}"
        aws iam detach-role-policy --role-name "${role_name}" --policy-arn "${policy_arn}"
      done
    else
      echo "No managed policies attached to role ${role_name}"
    fi

    # Delete inline policies
    local inline_policies
    inline_policies=$(aws iam list-role-policies --role-name "${role_name}" --query 'PolicyNames' --output text || echo "")
    if [ -n "${inline_policies}" ]; then
      for policy_name in ${inline_policies}; do
        echo "Deleting inline policy ${policy_name} from role ${role_name}"
        aws iam delete-role-policy --role-name "${role_name}" --policy-name "${policy_name}"
      done
    else
      echo "No inline policies found on role ${role_name}"
    fi

    echo "Deleting role ${role_name}"
    aws iam delete-role --role-name "${role_name}"
  else
    echo "Role ${role_name} does not exist, skipping role cleanup"
  fi
}

delete_user() {
  local user_name="$1"
  if aws iam get-user --user-name "${user_name}" > /dev/null 2>&1; then
    log "Deleting user ${user_name}"
    aws iam delete-user --user-name "${user_name}"
    log "User deleted: ${user_name}"
  else
    log "User ${user_name} does not exist, skipping user deletion"
  fi
}

delete_github_oidc_provider() {
  local aws_account_id
  aws_account_id=$(aws sts get-caller-identity --query Account --output text)
  
  local oidc_arn="arn:aws:iam::${aws_account_id}:oidc-provider/token.actions.githubusercontent.com"

  if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${oidc_arn}" >/dev/null 2>&1; then
    log "Deleting OIDC provider: ${oidc_arn}"
    aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "${oidc_arn}"
  else
    log "OIDC provider does not exist, skipping delete"
  fi
}

main() {

  cleanup_user "bootstrap"
  cleanup_role "Bootstrap"
  delete_user "bootstrap"
  cleanup_role "GithubActionsTerraformBootstrap"
  delete_github_oidc_provider

  echo "AWS resources cleanup completed."

  rm -rf .aws maxsportsanalysis-bootstrap-virtual-mfa.txt bootstrap.sh
}

main "$@"