#!/usr/bin/env bash
# Applies a JSON policy file as an inline policy on an IAM role.
# Safe to re-run — put-role-policy is idempotent.
#
# Usage:
#   ./scripts/apply-aws-iam-policy.sh <role-name> <json-policy-file>
#
# Examples:
#   ./scripts/apply-aws-iam-policy.sh github-tf-public-cloud-plan  scripts/iam/aws-plan-policy.json
#   ./scripts/apply-aws-iam-policy.sh github-tf-public-cloud-apply scripts/iam/aws-apply-policy.json
#
# Uses the 'sandbox' AWS CLI profile. Override by setting AWS_PROFILE before running.

set -euo pipefail
export AWS_PAGER=""

ROLE_NAME="${1:?Usage: $0 <role-name> <json-policy-file>}"
POLICY_FILE="${2:?Usage: $0 <role-name> <json-policy-file>}"

if [ ! -f "${POLICY_FILE}" ]; then
  echo "Error: policy file '${POLICY_FILE}' not found." >&2
  exit 1
fi

export AWS_PROFILE="${AWS_PROFILE:-sandbox}"

# Use the filename stem (without extension) as the inline policy name.
POLICY_NAME=$(basename "${POLICY_FILE}" .json)

echo "==> Applying IAM inline policy"
echo "    Role:        ${ROLE_NAME}"
echo "    Policy name: ${POLICY_NAME}"
echo "    Source file: ${POLICY_FILE}"
echo "    AWS profile: ${AWS_PROFILE}"
echo ""

echo "[VALIDATE] Checking JSON is valid..."
python3 -c "import sys,json; d=json.load(open(sys.argv[1])); assert 'Statement' in d" "${POLICY_FILE}"
echo "           OK"

echo "[APPLY] Putting inline policy on role..."
aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "${POLICY_NAME}" \
  --policy-document "file://${POLICY_FILE}"

echo ""
echo "==> Done. Verify with:"
echo "    aws iam get-role-policy --role-name ${ROLE_NAME} --policy-name ${POLICY_NAME} --profile ${AWS_PROFILE}"
