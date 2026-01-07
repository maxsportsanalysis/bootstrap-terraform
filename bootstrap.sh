#!/usr/bin/env bash
set -euo pipefail

############################################
# CONFIG
############################################

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

  if [[ ${#POSITIONAL_ARGS[@]} -ne 0 ]]; then
    error "Exactly two positional arguments required."
    usage
  fi
}

require_file() {
  [[ -f "$1" ]] || { echo "Missing file: $1"; exit 1; }
}

main() {
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION AWS_DEFAULT_REGION

  parse_args "$@"
  local iam_user_name="bootstrap"
  local bootstrap_mfa_device_name="maxsportsanalysis-bootstrap-virtual-mfa"
  local bootstrap_role_name="Bootstrap"

  local bootstrap_user_profile_name="${iam_user_name}-user"

  local aws_account_id
  aws_account_id=$(aws sts get-caller-identity --query Account --output text)
  log "AWS Account ID: ${aws_account_id}"

  aws iam get-user --user-name "${iam_user_name}" >/dev/null 2>&1 || aws iam create-user --user-name "${iam_user_name}"
  aws iam create-virtual-mfa-device --virtual-mfa-device-name "${bootstrap_mfa_device_name}" --bootstrap-method Base32StringSeed --outfile "./${bootstrap_mfa_device_name}.txt"
  sudo dnf install oathtool -y 
  mapfile -t codes < <(oathtool --base32 --totp "$(tr -d '\n' < ./${bootstrap_mfa_device_name}.txt)" -w 1)
  aws iam enable-mfa-device --user-name "${iam_user_name}" --serial-number "arn:aws:iam::${aws_account_id}:mfa/${bootstrap_mfa_device_name}" --authentication-code1 ${codes[0]} --authentication-code2 ${codes[1]}
  sleep 10
  aws iam create-role --role-name "${bootstrap_role_name}" --description "Bootstrap role for creating identity providers and IAM roles" --assume-role-policy-document file://<(cat <<EOF
{
  "Version":"2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::${aws_account_id}:user/${iam_user_name}" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "Bool": {
          "aws:MultiFactorAuthPresent": "true"
        }
      }
    }
  ]
}
EOF
)

  aws iam put-role-policy --role-name "${bootstrap_role_name}" --policy-name "${bootstrap_role_name}Permissions" --policy-document file://<(cat <<EOF
{
  "Version":"2012-10-17",		 	 	 
  "Statement": [
      {
          "Sid": "CreateResourcePermissions",
          "Effect": "Allow",
          "Action": [
            "iam:CreateOpenIDConnectProvider",
            "iam:CreateRole",
            "iam:CreatePolicy"
          ],
          "Resource": "*"
      },
      {
          "Sid": "AttachResourcePermissions",
          "Effect": "Allow",
          "Action": [
            "iam:PutRolePolicy"
          ],
          "Resource": "arn:aws:iam::${aws_account_id}:role/${bootstrap_role_name}"
      },
      {
          "Sid": "GetResourcePermissions",
          "Effect": "Allow",
          "Action": [
            "iam:GetOpenIDConnectProvider"
          ],
          "Resource": "arn:aws:iam::${aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
      },
      {
          "Sid": "DeleteResourcePermissions",
          "Effect": "Allow",
          "Action": [
            "iam:DeleteOpenIDConnectProvider"
          ],
          "Resource": "arn:aws:iam::${aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
  ]
}  
EOF
)

  aws iam put-user-policy --user-name "${iam_user_name}" --policy-name "Assume${bootstrap_role_name}Role" --policy-document file://<(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sts:AssumeRole",
    "Resource": "arn:aws:iam::${aws_account_id}:role/${bootstrap_role_name}"
  }]
}
EOF
)
  aws configure set profile.bootstrap.role_arn "arn:aws:iam::${aws_account_id}:role/${bootstrap_role_name}"
  aws configure set profile.bootstrap.source_profile "${bootstrap_user_profile_name}"
  aws configure set profile.bootstrap.mfa_serial "arn:aws:iam::${aws_account_id}:mfa/${bootstrap_mfa_device_name}"
  read access_key secret_key < <(aws iam create-access-key --user-name "${iam_user_name}" --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
  aws configure set aws_access_key_id "${access_key}" --profile "${bootstrap_user_profile_name}"
  aws configure set aws_secret_access_key "${secret_key}" --profile "${bootstrap_user_profile_name}"
  aws configure set region us-east-2 --profile "${bootstrap_user_profile_name}"
  aws configure set output json --profile "${bootstrap_user_profile_name}"
  sleep 10
  creds_json=$(aws sts assume-role --profile "${bootstrap_user_profile_name}" --role-arn "arn:aws:iam::${aws_account_id}:role/${bootstrap_role_name}" --role-session-name "bootstrap-session-$(date +%s)" --serial-number "arn:aws:iam::${aws_account_id}:mfa/${bootstrap_mfa_device_name}" --token-code "$(oathtool --base32 --totp "$(cat ./${bootstrap_mfa_device_name}.txt)" | tr -d ' \n\r')" --query 'Credentials' --output json)
  export AWS_ACCESS_KEY_ID=$(echo "${creds_json}" | jq -r '.AccessKeyId')
  export AWS_SECRET_ACCESS_KEY=$(echo "${creds_json}" | jq -r '.SecretAccessKey')
  export AWS_SESSION_TOKEN=$(echo "${creds_json}" | jq -r '.SessionToken')
  sleep 5
  aws sts get-caller-identity

  if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::${aws_account_id}:oidc-provider/token.actions.githubusercontent.com" >/dev/null 2>&1; then
    log "OIDC provider already exists: arn:aws:iam::${aws_account_id}:oidc-provider/token.actions.githubusercontent.com"
  else
    log "Creating GitHub OIDC Provider"
    aws iam create-open-id-connect-provider --url "https://token.actions.githubusercontent.com" --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" --client-id-list "sts.amazonaws.com"
  fi
  log "Completed Script..."
}

main "$@"



# aws sts assume-role \
# --role-session-name "bootstrap-$(date +%s)" \
# --role-arn arn:aws:iam::242201314218:role/Bootstrap \
# --output json | jq -r '.Credentials | "\(.AccessKeyId) \(.SecretAccessKey) \(.SessionToken)"' | \
# while read access_key secret_key session_token; do
#   aws configure set aws_access_key_id "${access_key}" --profile bootstrap-session
#   log "Configure AWS Access Key ID"
#   aws configure set aws_secret_access_key "${secret_key}" --profile bootstrap-session
#   log "Configure AWS Secret Access Key"
#   aws configure set aws_session_token "${session_token}" --profile bootstrap-session
#   export AWS_SESSION_TOKEN="${session_token}"
#   log "Configure AWS Access Key ID"
# done