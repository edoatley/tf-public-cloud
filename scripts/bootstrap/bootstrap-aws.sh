#!/usr/bin/env bash
# Full AWS bootstrap for Terraform remote state and GitHub Actions OIDC roles.
# Safe to re-run — checks for existence before creating each resource.
#
# What this script does:
#   1. Creates the S3 state bucket (versioning, SSE, public-access-block, HTTPS policy)
#   2. Creates the GitHub Actions OIDC Identity Provider (if it doesn't exist)
#   3. Creates the plan IAM role (trusted on pull_request events)
#   4. Creates the apply IAM role (trusted on push to main)
#   5. Applies inline policies from scripts/iam/ to both roles
#
# State locking uses S3 native locking (use_lockfile = true) — no DynamoDB required.
#
# Usage:
#   ./scripts/bootstrap-aws.sh
#
# Uses the 'sandbox' AWS CLI profile. Override by setting AWS_PROFILE before running.
# Edit the variables below to change resource names.

set -euo pipefail
export AWS_PAGER=""

export AWS_PROFILE="${AWS_PROFILE:-sandbox}"

AWS_REGION=eu-west-2
TF_STATE_BUCKET=tf-public-cloud-aws-state-edo
GITHUB_ORG=edoatley
GITHUB_REPO=tf-public-cloud
PLAN_ROLE_NAME=github-tf-public-cloud-plan
APPLY_ROLE_NAME=github-tf-public-cloud-apply
OIDC_PROVIDER_URL=https://token.actions.githubusercontent.com
OIDC_AUDIENCE=sts.amazonaws.com

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [AWS] Bootstrapping Terraform state backend"
echo "    Region:  ${AWS_REGION}"
echo "    Bucket:  ${TF_STATE_BUCKET}"
echo ""

# ---------- S3 state bucket ----------

if aws s3api head-bucket --bucket "${TF_STATE_BUCKET}" --region "${AWS_REGION}" 2>/dev/null; then
  echo "[SKIP] Bucket '${TF_STATE_BUCKET}' already exists."
else
  echo "[CREATE] Creating S3 bucket '${TF_STATE_BUCKET}'..."
  if [ "${AWS_REGION}" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "${TF_STATE_BUCKET}" \
      --region "${AWS_REGION}"
  else
    aws s3api create-bucket \
      --bucket "${TF_STATE_BUCKET}" \
      --region "${AWS_REGION}" \
      --create-bucket-configuration LocationConstraint="${AWS_REGION}"
  fi
fi

echo "[CONFIG] Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "${TF_STATE_BUCKET}" \
  --versioning-configuration Status=Enabled

echo "[CONFIG] Enabling server-side encryption (AES-256)..."
aws s3api put-bucket-encryption \
  --bucket "${TF_STATE_BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }'

echo "[CONFIG] Blocking all public access..."
aws s3api put-public-access-block \
  --bucket "${TF_STATE_BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "[CONFIG] Enforcing HTTPS-only access via bucket policy..."
aws s3api put-bucket-policy \
  --bucket "${TF_STATE_BUCKET}" \
  --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"DenyNonHTTPS\",
      \"Effect\": \"Deny\",
      \"Principal\": \"*\",
      \"Action\": \"s3:*\",
      \"Resource\": [
        \"arn:aws:s3:::${TF_STATE_BUCKET}\",
        \"arn:aws:s3:::${TF_STATE_BUCKET}/*\"
      ],
      \"Condition\": {
        \"Bool\": { \"aws:SecureTransport\": \"false\" }
      }
    }]
  }"

# ---------- GitHub Actions OIDC Identity Provider ----------

echo ""
echo "==> [AWS] Setting up GitHub Actions OIDC Identity Provider"

OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${OIDC_ARN}" 2>/dev/null | grep -q Url; then
  echo "[SKIP] OIDC provider already exists."
else
  echo "[CREATE] Creating OIDC identity provider..."
  aws iam create-open-id-connect-provider \
    --url "${OIDC_PROVIDER_URL}" \
    --client-id-list "${OIDC_AUDIENCE}" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"
fi

# ---------- IAM roles ----------

create_or_update_role() {
  local ROLE_NAME="$1"
  local TRUST_POLICY="$2"

  if aws iam get-role --role-name "${ROLE_NAME}" 2>/dev/null | grep -q RoleName; then
    echo "[UPDATE] Role '${ROLE_NAME}' already exists — updating trust policy..."
    aws iam update-assume-role-policy \
      --role-name "${ROLE_NAME}" \
      --policy-document "${TRUST_POLICY}"
  else
    echo "[CREATE] Creating IAM role '${ROLE_NAME}'..."
    aws iam create-role \
      --role-name "${ROLE_NAME}" \
      --assume-role-policy-document "${TRUST_POLICY}" \
      --description "Assumed by GitHub Actions via OIDC for ${GITHUB_ORG}/${GITHUB_REPO}"
  fi
}

echo ""
echo "==> [AWS] Creating GitHub Actions IAM roles"

PLAN_TRUST=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "${OIDC_AUDIENCE}"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
      }
    }
  }]
}
EOF
)

APPLY_TRUST=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "${OIDC_AUDIENCE}",
        "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:production"
      }
    }
  }]
}
EOF
)

create_or_update_role "${PLAN_ROLE_NAME}"  "${PLAN_TRUST}"
create_or_update_role "${APPLY_ROLE_NAME}" "${APPLY_TRUST}"

# ---------- Inline policies ----------

echo ""
echo "==> [AWS] Applying inline policies"

apply_policy() {
  local ROLE_NAME="$1"
  local POLICY_FILE="$2"
  local POLICY_NAME
  POLICY_NAME=$(basename "${POLICY_FILE}" .json)
  echo "[APPLY] ${POLICY_NAME} -> ${ROLE_NAME}"
  aws iam put-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name "${POLICY_NAME}" \
    --policy-document "file://${POLICY_FILE}"
}

apply_policy "${PLAN_ROLE_NAME}"  "${SCRIPT_DIR}/../iam/aws-plan-policy.json"
apply_policy "${APPLY_ROLE_NAME}" "${SCRIPT_DIR}/../iam/aws-apply-policy.json"

# ---------- Summary ----------

echo ""
echo "==> [AWS] Bootstrap complete."
echo ""
echo "    Add the following to aws/*/backend.tf:"
echo "    bucket       = \"${TF_STATE_BUCKET}\""
echo "    region       = \"${AWS_REGION}\""
echo "    use_lockfile = true"
echo ""
echo "    Set the following GitHub Actions Variables:"
echo "    AWS_ROLE_ARN      = arn:aws:iam::${ACCOUNT_ID}:role/${APPLY_ROLE_NAME}"
echo "    AWS_PLAN_ROLE_ARN = arn:aws:iam::${ACCOUNT_ID}:role/${PLAN_ROLE_NAME}"
echo "    AWS_REGION        = ${AWS_REGION}"
