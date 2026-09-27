#!/usr/bin/env bash
# Full Azure bootstrap for Terraform remote state and GitHub Actions OIDC federation.
# Safe to re-run — checks for existence before creating each resource.
#
# What this script does:
#   1. Creates the Resource Group and Storage Account for Terraform state
#   2. Creates the Blob Container for state files
#   3. Creates an App Registration and Service Principal for GitHub Actions
#   4. Creates a 'default' GitHub Actions environment
#   5. Adds a Federated Credential for the 'default' environment (covers all branches)
#   6. Creates the examples Resource Group
#   7. Applies RBAC assignments from scripts/iam/azure-plan-permissions.json and
#      scripts/iam/azure-apply-permissions.json
#
# Usage:
#   ./scripts/bootstrap-azure.sh
#
# Requires: az CLI, authenticated with Owner or equivalent on the subscription.
# Edit the variables below to change resource names.

set -euo pipefail

AZ_SUBSCRIPTION=edbc314c-06b5-431f-bcc9-40267e377669
AZ_TENANT=f20d4ab3-33a2-4154-b703-9f6ede9268f8
AZ_LOCATION=uksouth
AZ_STATE_RG=rg-tf-public-cloud-state
AZ_STATE_STORAGE=tfpubliccloudazstate      # 3-24 lowercase alphanumeric, globally unique
AZ_STATE_CONTAINER=tfstate
AZ_EXAMPLES_RG=rg-tf-public-cloud-examples
PLAN_APP_NAME=github-tf-public-cloud-plan
APPLY_APP_NAME=github-tf-public-cloud-apply
GITHUB_ORG=edoatley
GITHUB_REPO=tf-public-cloud

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [Azure] Bootstrapping Terraform state backend and GitHub Actions OIDC"
echo "    Subscription:     ${AZ_SUBSCRIPTION}"
echo "    Location:         ${AZ_LOCATION}"
echo "    State RG:         ${AZ_STATE_RG}"
echo "    State account:    ${AZ_STATE_STORAGE}"
echo "    Examples RG:      ${AZ_EXAMPLES_RG}"
echo "    Plan app:         ${PLAN_APP_NAME}"
echo "    Apply app:        ${APPLY_APP_NAME}"
echo ""

az account set --subscription "${AZ_SUBSCRIPTION}"

# ---------- Resource Provider Registration ----------

echo "==> [Azure] Ensuring required resource providers are registered"
for PROVIDER in Microsoft.Storage Microsoft.Authorization Microsoft.Network Microsoft.Compute Microsoft.ContainerRegistry Microsoft.App Microsoft.Web; do
  STATE=$(az provider show --namespace "${PROVIDER}" --query 'registrationState' --output tsv 2>/dev/null)
  if [ "${STATE}" = "Registered" ]; then
    echo "[SKIP] ${PROVIDER} already registered."
  else
    echo "[REGISTER] Registering ${PROVIDER}..."
    az provider register --namespace "${PROVIDER}" --wait
    echo "[OK] ${PROVIDER} registered."
  fi
done

# ---------- State Resource Group ----------

echo "==> [Azure] Setting up state resource group"

if az group show --name "${AZ_STATE_RG}" 2>/dev/null | grep -q '"name"'; then
  echo "[SKIP] Resource group '${AZ_STATE_RG}' already exists."
else
  echo "[CREATE] Creating resource group '${AZ_STATE_RG}'..."
  az group create --name "${AZ_STATE_RG}" --location "${AZ_LOCATION}" --output none
  echo "[WAIT] Waiting for resource group to be ready..."
  az group wait --name "${AZ_STATE_RG}" --created
fi

# ---------- State Storage Account ----------

echo ""
echo "==> [Azure] Setting up state storage account"

if az storage account show --name "${AZ_STATE_STORAGE}" --resource-group "${AZ_STATE_RG}" 2>/dev/null | grep -q '"name"'; then
  echo "[SKIP] Storage account '${AZ_STATE_STORAGE}' already exists."
else
  echo "[CREATE] Creating storage account '${AZ_STATE_STORAGE}'..."
  az storage account create \
    --name "${AZ_STATE_STORAGE}" \
    --resource-group "${AZ_STATE_RG}" \
    --location "${AZ_LOCATION}" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --https-only true \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --output none
fi

echo "[CONFIG] Enabling blob versioning..."
az storage account blob-service-properties update \
  --account-name "${AZ_STATE_STORAGE}" \
  --resource-group "${AZ_STATE_RG}" \
  --enable-versioning true \
  --output none

# ---------- State Blob Container ----------

if az storage container show \
    --name "${AZ_STATE_CONTAINER}" \
    --account-name "${AZ_STATE_STORAGE}" \
    --auth-mode login 2>/dev/null | grep -q '"name"'; then
  echo "[SKIP] Container '${AZ_STATE_CONTAINER}' already exists."
else
  echo "[CREATE] Creating blob container '${AZ_STATE_CONTAINER}'..."
  az storage container create \
    --name "${AZ_STATE_CONTAINER}" \
    --account-name "${AZ_STATE_STORAGE}" \
    --public-access off \
    --auth-mode login \
    --output none
fi

# ---------- Examples Resource Group ----------

echo ""
echo "==> [Azure] Setting up examples resource group"

if az group show --name "${AZ_EXAMPLES_RG}" 2>/dev/null | grep -q '"name"'; then
  echo "[SKIP] Resource group '${AZ_EXAMPLES_RG}' already exists."
else
  echo "[CREATE] Creating resource group '${AZ_EXAMPLES_RG}'..."
  az group create --name "${AZ_EXAMPLES_RG}" --location "${AZ_LOCATION}" --output none
fi

# ---------- App Registrations ----------

create_or_get_app() {
  local NAME="$1"
  local ID
  ID=$(az ad app list --display-name "${NAME}" --query '[0].appId' --output tsv 2>/dev/null)
  if [ -n "${ID}" ] && [ "${ID}" != "None" ]; then
    echo "[SKIP] App registration '${NAME}' already exists (client ID: ${ID})." >&2
  else
    echo "[CREATE] Creating app registration '${NAME}'..." >&2
    ID=$(az ad app create --display-name "${NAME}" --query appId --output tsv)
    echo "[OK] Created app with client ID: ${ID}" >&2
    echo "[CREATE] Creating service principal..." >&2
    az ad sp create --id "${ID}" --output none
  fi
  echo "${ID}"
}

echo ""
echo "==> [Azure] Setting up App Registrations"
PLAN_APP_ID=$(create_or_get_app "${PLAN_APP_NAME}")
APPLY_APP_ID=$(create_or_get_app "${APPLY_APP_NAME}")

# ---------- GitHub Environments ----------

echo ""
echo "==> [GitHub] Setting up environments"

ensure_github_env() {
  local ENV_NAME="$1"
  if gh api "repos/${GITHUB_ORG}/${GITHUB_REPO}/environments/${ENV_NAME}" --silent 2>/dev/null; then
    echo "[SKIP] GitHub environment '${ENV_NAME}' already exists."
  else
    echo "[CREATE] Creating GitHub environment '${ENV_NAME}'..."
    gh api --method PUT "repos/${GITHUB_ORG}/${GITHUB_REPO}/environments/${ENV_NAME}" --silent
    echo "[OK] Created."
  fi
}

ensure_github_env "default"
ensure_github_env "production"

# ---------- Federated Credentials ----------

echo ""
echo "==> [Azure] Setting up Federated Credentials"

add_federated_credential() {
  local APP_ID="$1"
  local NAME="$2"
  local SUBJECT="$3"
  local DESCRIPTION="$4"

  EXISTING=$(az ad app federated-credential list --id "${APP_ID}" \
    --query "[?name=='${NAME}'].name" --output tsv 2>/dev/null)

  if [ -n "${EXISTING}" ]; then
    echo "[SKIP] Federated credential '${NAME}' already exists."
  else
    echo "[CREATE] Adding federated credential '${NAME}'..."
    az ad app federated-credential create \
      --id "${APP_ID}" \
      --parameters "{
        \"name\": \"${NAME}\",
        \"issuer\": \"https://token.actions.githubusercontent.com\",
        \"subject\": \"${SUBJECT}\",
        \"description\": \"${DESCRIPTION}\",
        \"audiences\": [\"api://AzureADTokenExchange\"]
      }" \
      --output none
  fi
}

# Plan app — trusts jobs running in the 'default' environment (PRs, branches, dispatch).
# Azure does not support wildcard subjects spanning multiple claim segments, so an
# environment credential is the cleanest way to cover all non-privileged workflow jobs.
add_federated_credential \
  "${PLAN_APP_ID}" \
  "GHA-Default-Creds" \
  "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:default" \
  "GitHub Actions — default environment (plan / read-only)"

# Apply app — trusts jobs running in the 'production' environment only.
# The production environment requires reviewer approval and is restricted to
# release-* tags, so the federated credential and the environment gate are
# independent controls that must both pass before write credentials are issued.
add_federated_credential \
  "${APPLY_APP_ID}" \
  "GHA-Production-Creds" \
  "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:production" \
  "GitHub Actions — production environment (apply / write)"

# ---------- GitHub environment-level variables ----------

echo ""
echo "==> [GitHub] Setting environment-level AZURE_CLIENT_ID variables"

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

set_github_env_var "default"    "AZURE_CLIENT_ID" "${PLAN_APP_ID}"
set_github_env_var "production" "AZURE_CLIENT_ID" "${APPLY_APP_ID}"

# ---------- RBAC assignments ----------

echo ""
echo "==> [Azure] Applying RBAC assignments"
echo "    Plan app  (${PLAN_APP_ID}) -> azure-plan-permissions.json"
"${SCRIPT_DIR}/apply-azure-rbac.sh" "${PLAN_APP_ID}"  "${SCRIPT_DIR}/../iam/azure-plan-permissions.json"
echo "    Apply app (${APPLY_APP_ID}) -> azure-apply-permissions.json"
"${SCRIPT_DIR}/apply-azure-rbac.sh" "${APPLY_APP_ID}" "${SCRIPT_DIR}/../iam/azure-apply-permissions.json"

# ---------- RBAC assignments (current user) ----------

echo ""
echo "==> [Azure] Granting Storage Blob Data Contributor to current user on state storage account"

CURRENT_USER_ID=$(az ad signed-in-user show --query id --output tsv 2>/dev/null || true)

if [ -z "${CURRENT_USER_ID}" ]; then
  echo "[SKIP] Could not determine current user identity — skipping user RBAC grant."
else
  STATE_STORAGE_SCOPE="/subscriptions/${AZ_SUBSCRIPTION}/resourceGroups/${AZ_STATE_RG}/providers/Microsoft.Storage/storageAccounts/${AZ_STATE_STORAGE}"
  EXISTING=$(az role assignment list \
    --assignee "${CURRENT_USER_ID}" \
    --role "Storage Blob Data Contributor" \
    --scope "${STATE_STORAGE_SCOPE}" \
    --query "length(@)" --output tsv 2>/dev/null || echo "0")
  if [ "${EXISTING}" != "0" ]; then
    echo "[SKIP] Current user already has Storage Blob Data Contributor on ${AZ_STATE_STORAGE}."
  else
    echo "[CREATE] Assigning Storage Blob Data Contributor to current user on ${AZ_STATE_STORAGE}..."
    az role assignment create \
      --assignee "${CURRENT_USER_ID}" \
      --role "Storage Blob Data Contributor" \
      --scope "${STATE_STORAGE_SCOPE}" \
      --output none
    echo "[OK] Assigned."
  fi
fi

# ---------- Summary ----------

echo ""
echo "==> [Azure] Bootstrap complete."
echo ""
echo "    Add the following to azure/*/backend.tf:"
echo "    resource_group_name  = \"${AZ_STATE_RG}\""
echo "    storage_account_name = \"${AZ_STATE_STORAGE}\""
echo "    container_name       = \"${AZ_STATE_CONTAINER}\""
echo ""
echo "    Set the following GitHub Actions repo-level Variables:"
echo "    AZURE_TENANT_ID       = ${AZ_TENANT}"
echo "    AZURE_SUBSCRIPTION_ID = ${AZ_SUBSCRIPTION}"
echo ""
echo "    Environment-level AZURE_CLIENT_ID has been set automatically:"
echo "    default    -> ${PLAN_APP_ID}  (plan / read-only)"
echo "    production -> ${APPLY_APP_ID} (apply / write)"
