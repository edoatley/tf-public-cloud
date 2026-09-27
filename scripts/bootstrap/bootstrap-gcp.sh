#!/usr/bin/env bash
# Full GCP bootstrap for Terraform remote state and GitHub Actions Workload Identity Federation.
# Safe to re-run — checks for existence before creating each resource.
#
# What this script does:
#   1. Enables required GCP APIs
#   2. Creates the GCS state bucket (uniform access, versioning, public access prevention)
#   3. Creates a Workload Identity Pool and OIDC Provider for GitHub Actions
#   4. Creates a Service Account for GitHub Actions
#   5. Binds the WIF provider to the Service Account
#   6. Grants the Service Account storage permissions on the state bucket
#
# Usage:
#   ./scripts/bootstrap-gcp.sh
#
# Requires: gcloud CLI, authenticated with sufficient permissions (Owner or equivalent).
# Edit the variables below to change resource names.

set -euo pipefail

GCP_PROJECT=gcp-sandbox-2026-18798
GCP_REGION=europe-west2
TF_STATE_BUCKET=tf-public-cloud-gcp-state-edo
GITHUB_ORG=edoatley
GITHUB_REPO=tf-public-cloud
WIF_POOL_ID=github-pool
WIF_PROVIDER_ID=github-provider
GSA_PLAN_NAME=github-actions-tf-plan
GSA_APPLY_NAME=github-actions-tf-apply

# Derived values — do not edit
GSA_PLAN_EMAIL="${GSA_PLAN_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
GSA_APPLY_EMAIL="${GSA_APPLY_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
PROJECT_NUMBER=$(gcloud projects describe "${GCP_PROJECT}" --format="value(projectNumber)")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [GCP] Bootstrapping Terraform state backend and GitHub Actions WIF"
echo "    Project:        ${GCP_PROJECT} (${PROJECT_NUMBER})"
echo "    Region:         ${GCP_REGION}"
echo "    State bucket:   gs://${TF_STATE_BUCKET}"
echo "    WIF pool:        ${WIF_POOL_ID}"
echo "    Plan SA:         ${GSA_PLAN_EMAIL}"
echo "    Apply SA:        ${GSA_APPLY_EMAIL}"
echo ""

# ---------- Enable required APIs ----------

echo "==> [GCP] Enabling required APIs..."
gcloud services enable \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  cloudresourcemanager.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  compute.googleapis.com \
  servicedirectory.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  --project="${GCP_PROJECT}"
echo "[OK] APIs enabled."

# ---------- GCS state bucket ----------

echo ""
echo "==> [GCP] Setting up state bucket"

if gcloud storage buckets describe "gs://${TF_STATE_BUCKET}" --project="${GCP_PROJECT}" 2>/dev/null | grep -q name; then
  echo "[SKIP] Bucket 'gs://${TF_STATE_BUCKET}' already exists."
else
  echo "[CREATE] Creating GCS bucket 'gs://${TF_STATE_BUCKET}'..."
  gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
    --project="${GCP_PROJECT}" \
    --location="${GCP_REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

echo "[CONFIG] Enabling versioning..."
gcloud storage buckets update "gs://${TF_STATE_BUCKET}" \
  --versioning \
  --uniform-bucket-level-access \
  --public-access-prevention

# ---------- Workload Identity Pool ----------

echo ""
echo "==> [GCP] Setting up Workload Identity Federation"

if gcloud iam workload-identity-pools describe "${WIF_POOL_ID}" \
    --location=global --project="${GCP_PROJECT}" 2>/dev/null | grep -q name; then
  echo "[SKIP] WIF pool '${WIF_POOL_ID}' already exists."
else
  echo "[CREATE] Creating Workload Identity Pool '${WIF_POOL_ID}'..."
  gcloud iam workload-identity-pools create "${WIF_POOL_ID}" \
    --location=global \
    --display-name="GitHub Actions pool" \
    --project="${GCP_PROJECT}"
fi

# ---------- Workload Identity Provider ----------

if gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_ID}" \
    --workload-identity-pool="${WIF_POOL_ID}" \
    --location=global --project="${GCP_PROJECT}" 2>/dev/null | grep -q name; then
  echo "[UPDATE] WIF provider '${WIF_PROVIDER_ID}' exists — updating attribute mapping..."
  gcloud iam workload-identity-pools providers update-oidc "${WIF_PROVIDER_ID}" \
    --workload-identity-pool="${WIF_POOL_ID}" \
    --location=global \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref,attribute.environment=assertion.environment" \
    --attribute-condition="assertion.repository == \"${GITHUB_ORG}/${GITHUB_REPO}\"" \
    --project="${GCP_PROJECT}"
else
  echo "[CREATE] Creating OIDC provider '${WIF_PROVIDER_ID}'..."
  gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER_ID}" \
    --workload-identity-pool="${WIF_POOL_ID}" \
    --location=global \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref,attribute.environment=assertion.environment" \
    --attribute-condition="assertion.repository == \"${GITHUB_ORG}/${GITHUB_REPO}\"" \
    --project="${GCP_PROJECT}"
fi

# ---------- Service Accounts ----------

echo ""
echo "==> [GCP] Setting up Service Accounts"

create_or_skip_sa() {
  local NAME="$1"
  local EMAIL="$2"
  local DISPLAY="$3"
  if gcloud iam service-accounts describe "${EMAIL}" --project="${GCP_PROJECT}" 2>/dev/null | grep -q email; then
    echo "[SKIP] Service account '${EMAIL}' already exists."
  else
    echo "[CREATE] Creating service account '${NAME}'..."
    gcloud iam service-accounts create "${NAME}" \
      --display-name="${DISPLAY}" \
      --project="${GCP_PROJECT}"
  fi
}

create_or_skip_sa "${GSA_PLAN_NAME}"  "${GSA_PLAN_EMAIL}"  "GitHub Actions Terraform — plan (read-only)"
create_or_skip_sa "${GSA_APPLY_NAME}" "${GSA_APPLY_EMAIL}" "GitHub Actions Terraform — apply (write)"

# ---------- Bind WIF provider to Service Accounts ----------

echo ""
echo "==> [GCP] Binding WIF provider to service accounts"

# Plan SA — trusted for any token from this repository (any branch, PR, or dispatch)
echo "[CONFIG] Binding plan SA via repository attribute..."
gcloud iam service-accounts add-iam-policy-binding "${GSA_PLAN_EMAIL}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}" \
  --project="${GCP_PROJECT}"

# Apply SA — trusted only for tokens carrying environment:production
# (GitHub sets this claim when a job declares `environment: production`)
echo "[CONFIG] Binding apply SA via environment:production attribute..."
gcloud iam service-accounts add-iam-policy-binding "${GSA_APPLY_EMAIL}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/attribute.environment/production" \
  --project="${GCP_PROJECT}"

# ---------- Grant IAM permissions ----------

echo ""
echo "==> [GCP] Applying IAM bindings"
echo "    Plan SA  (${GSA_PLAN_EMAIL}) -> gcp-plan-permissions.json"
"${SCRIPT_DIR}/apply-gcp-iam-bindings.sh" "${GSA_PLAN_EMAIL}"  "${SCRIPT_DIR}/../iam/gcp-plan-permissions.json"
echo "    Apply SA (${GSA_APPLY_EMAIL}) -> gcp-apply-permissions.json"
"${SCRIPT_DIR}/apply-gcp-iam-bindings.sh" "${GSA_APPLY_EMAIL}" "${SCRIPT_DIR}/../iam/gcp-apply-permissions.json"

# ---------- GitHub environment-level variables ----------

echo ""
echo "==> [GitHub] Setting environment-level GCP_SERVICE_ACCOUNT variables"

set_github_env_var() {
  local ENV_NAME="$1"
  local VAR_NAME="$2"
  local VAR_VALUE="$3"
  echo "[SET] ${ENV_NAME}::${VAR_NAME} = ${VAR_VALUE}"
  gh api --method POST \
    "repos/${GITHUB_ORG}/${GITHUB_REPO}/environments/${ENV_NAME}/variables" \
    --field name="${VAR_NAME}" \
    --field value="${VAR_VALUE}" 2>/dev/null || \
  gh api --method PATCH \
    "repos/${GITHUB_ORG}/${GITHUB_REPO}/environments/${ENV_NAME}/variables/${VAR_NAME}" \
    --field name="${VAR_NAME}" \
    --field value="${VAR_VALUE}"
}

set_github_env_var "default"    "GCP_SERVICE_ACCOUNT" "${GSA_PLAN_EMAIL}"
set_github_env_var "production" "GCP_SERVICE_ACCOUNT" "${GSA_APPLY_EMAIL}"

# ---------- Summary ----------

WIF_PROVIDER_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/providers/${WIF_PROVIDER_ID}"

echo ""
echo "==> [GCP] Bootstrap complete."
echo ""
echo "    Add the following to gcp/*/backend.tf:"
echo "    bucket = \"${TF_STATE_BUCKET}\""
echo ""
echo "    Set the following GitHub Actions repo-level Variables:"
echo "    GCP_WIF_PROVIDER = ${WIF_PROVIDER_RESOURCE}"
echo "    GCP_PROJECT_ID   = ${GCP_PROJECT}"
echo ""
echo "    Environment-level GCP_SERVICE_ACCOUNT has been set automatically:"
echo "    default    -> ${GSA_PLAN_EMAIL}  (plan / read-only)"
echo "    production -> ${GSA_APPLY_EMAIL} (apply / write)"
