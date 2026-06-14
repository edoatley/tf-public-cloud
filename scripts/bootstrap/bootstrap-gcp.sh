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
GSA_NAME=github-actions-tf

# Derived values — do not edit
GSA_EMAIL="${GSA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
PROJECT_NUMBER=$(gcloud projects describe "${GCP_PROJECT}" --format="value(projectNumber)")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [GCP] Bootstrapping Terraform state backend and GitHub Actions WIF"
echo "    Project:        ${GCP_PROJECT} (${PROJECT_NUMBER})"
echo "    Region:         ${GCP_REGION}"
echo "    State bucket:   gs://${TF_STATE_BUCKET}"
echo "    WIF pool:       ${WIF_POOL_ID}"
echo "    Service account: ${GSA_EMAIL}"
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
  echo "[SKIP] WIF provider '${WIF_PROVIDER_ID}' already exists."
else
  echo "[CREATE] Creating OIDC provider '${WIF_PROVIDER_ID}'..."
  gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER_ID}" \
    --workload-identity-pool="${WIF_POOL_ID}" \
    --location=global \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository == \"${GITHUB_ORG}/${GITHUB_REPO}\"" \
    --project="${GCP_PROJECT}"
fi

# ---------- Service Account ----------

echo ""
echo "==> [GCP] Setting up Service Account"

if gcloud iam service-accounts describe "${GSA_EMAIL}" --project="${GCP_PROJECT}" 2>/dev/null | grep -q email; then
  echo "[SKIP] Service account '${GSA_EMAIL}' already exists."
else
  echo "[CREATE] Creating service account '${GSA_NAME}'..."
  gcloud iam service-accounts create "${GSA_NAME}" \
    --display-name="GitHub Actions Terraform" \
    --project="${GCP_PROJECT}"
fi

# ---------- Bind WIF provider to Service Account ----------

echo "[CONFIG] Binding WIF provider to service account..."
gcloud iam service-accounts add-iam-policy-binding "${GSA_EMAIL}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}" \
  --project="${GCP_PROJECT}"

# ---------- Grant IAM permissions ----------

echo ""
echo "==> [GCP] Applying IAM bindings from scripts/iam/gcp-permissions.json"
"${SCRIPT_DIR}/apply-gcp-iam-bindings.sh" "${GSA_EMAIL}" "${SCRIPT_DIR}/../iam/gcp-permissions.json"

# ---------- Summary ----------

WIF_PROVIDER_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/providers/${WIF_PROVIDER_ID}"

echo ""
echo "==> [GCP] Bootstrap complete."
echo ""
echo "    Add the following to gcp/*/backend.tf:"
echo "    bucket = \"${TF_STATE_BUCKET}\""
echo ""
echo "    Set the following GitHub Actions Variables:"
echo "    GCP_WIF_PROVIDER    = ${WIF_PROVIDER_RESOURCE}"
echo "    GCP_SERVICE_ACCOUNT = ${GSA_EMAIL}"
