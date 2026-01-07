#!/usr/bin/env bash
set -euo pipefail

USER="bootstrap"
ROLE_NAME="Bootstrap"

# Check if user exists
if ! aws iam get-user --user-name "${USER}" > /dev/null 2>&1; then
  echo "User ${USER} does not exist, skipping user cleanup"
else
  echo "Cleaning up access keys for user ${USER}..."
  KEYS=$(aws iam list-access-keys --user-name "${USER}" --query 'AccessKeyMetadata[].AccessKeyId' --output text || echo "")

  if [ -n "${KEYS}" ]; then
    for KEY in ${KEYS}; do
      echo "Deactivating key ${KEY}"
      aws iam update-access-key --user-name "${USER}" --access-key-id "${KEY}" --status Inactive
      echo "Deleting key ${KEY}"
      aws iam delete-access-key --user-name "${USER}" --access-key-id "${KEY}"
    done
  else
    echo "No access keys found for user ${USER}"
  fi

  echo "Deleting user inline policies for ${USER}..."
  USER_POLICIES=$(aws iam list-user-policies --user-name "${USER}" --query 'PolicyNames' --output text || echo "")
  if [ -n "${USER_POLICIES}" ]; then
    for USER_POLICY_NAME in ${USER_POLICIES}; do
      echo "Deleting user policy ${USER_POLICY_NAME} from user ${USER}"
      aws iam delete-user-policy --user-name "${USER}" --policy-name "${USER_POLICY_NAME}"
    done
  else
    echo "No user inline policies found for user ${USER}"
  fi

  echo "Deactivating and deleting MFA devices for user ${USER}..."
  MFA_DEVICES=$(aws iam list-mfa-devices --user-name "${USER}" --query 'MFADevices[].SerialNumber' --output text || echo "")
  if [ -n "${MFA_DEVICES}" ]; then
    for mfa in ${MFA_DEVICES}; do
      echo "Deactivating MFA device ${mfa}"
      aws iam deactivate-mfa-device --user-name "${USER}" --serial-number "${mfa}"
      echo "Deleting virtual MFA device ${mfa}"
      aws iam delete-virtual-mfa-device --serial-number "${mfa}"
    done
  else
    echo "No MFA devices found for user ${USER}"
  fi
fi

# Role cleanup
if aws iam get-role --role-name "${ROLE_NAME}" > /dev/null 2>&1; then
  echo "Cleaning up role ${ROLE_NAME}..."

  # Detach managed policies
  POLICIES=$(aws iam list-attached-role-policies --role-name "${ROLE_NAME}" --query 'AttachedPolicies[].PolicyArn' --output text || echo "")
  if [ -n "${POLICIES}" ]; then
    for POLICY_ARN in ${POLICIES}; do
      echo "Detaching managed policy ${POLICY_ARN} from role ${ROLE_NAME}"
      aws iam detach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${POLICY_ARN}"
    done
  else
    echo "No managed policies attached to role ${ROLE_NAME}"
  fi

  # Delete inline policies
  INLINE_POLICIES=$(aws iam list-role-policies --role-name "${ROLE_NAME}" --query 'PolicyNames' --output text || echo "")
  if [ -n "${INLINE_POLICIES}" ]; then
    for POLICY_NAME in ${INLINE_POLICIES}; do
      echo "Deleting inline policy ${POLICY_NAME} from role ${ROLE_NAME}"
      aws iam delete-role-policy --role-name "${ROLE_NAME}" --policy-name "${POLICY_NAME}"
    done
  else
    echo "No inline policies found on role ${ROLE_NAME}"
  fi

  echo "Deleting role ${ROLE_NAME}"
  aws iam delete-role --role-name "${ROLE_NAME}"
else
  echo "Role ${ROLE_NAME} does not exist, skipping role cleanup"
fi

# Finally delete the user if exists
if aws iam get-user --user-name "${USER}" > /dev/null 2>&1; then
  echo "Deleting user ${USER}"
  aws iam delete-user --user-name "${USER}"
  echo "User deleted: ${USER}"
else
  echo "User ${USER} does not exist, skipping user deletion"
fi

echo "AWS resources cleanup completed."

rm -rf .aws maxsportsanalysis-bootstrap-virtual-mfa.txt bootstrap.sh