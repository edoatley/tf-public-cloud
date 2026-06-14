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
#   7. Applies RBAC assignments from scripts/iam/azure-permissions.json
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
APP_NAME=github-tf-public-cloud
GITHUB_ORG=edoatley
GITHUB_REPO=tf-public-cloud

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [Azure] Bootstrapping Terraform state backend and GitHub Actions OIDC"
echo "    Subscription:     ${AZ_SUBSCRIPTION}"
echo "    Location:         ${AZ_LOCATION}"
echo "    State RG:         ${AZ_STATE_RG}"
echo "    State account:    ${AZ_STATE_STORAGE}"
echo "    Examples RG:      ${AZ_EXAMPLES_RG}"
echo "    App registration: ${APP_NAME}"
echo ""

az account set --subscription "${AZ_SUBSCRIPTION}"

# ---------- Resource Provider Registration ----------

echo "==> [Azure] Ensuring required resource providers are registered"
for PROVIDER in Microsoft.Storage Microsoft.Authorization Microsoft.Network Microsoft.Compute Microsoft.ContainerRegistry Microsoft.App; do
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

# ---------- App Registration ----------

echo ""
echo "==> [Azure] Setting up App Registration"

APP_ID=$(az ad app list --display-name "${APP_NAME}" --query '[0].appId' --output tsv 2>/dev/null)

if [ -n "${APP_ID}" ] && [ "${APP_ID}" != "None" ]; then
  echo "[SKIP] App registration '${APP_NAME}' already exists (client ID: ${APP_ID})."
else
  echo "[CREATE] Creating app registration '${APP_NAME}'..."
  APP_ID=$(az ad app create \
    --display-name "${APP_NAME}" \
    --query appId \
    --output tsv)
  echo "[OK] Created app with client ID: ${APP_ID}"

  echo "[CREATE] Creating service principal..."
  az ad sp create --id "${APP_ID}" --output none
fi

# ---------- GitHub Environment ----------

echo ""
echo "==> [GitHub] Setting up 'default' environment"

if gh api "repos/${GITHUB_ORG}/${GITHUB_REPO}/environments/default" --silent 2>/dev/null; then
  echo "[SKIP] GitHub environment 'default' already exists."
else
  echo "[CREATE] Creating GitHub environment 'default'..."
  gh api --method PUT "repos/${GITHUB_ORG}/${GITHUB_REPO}/environments/default" --silent
  echo "[OK] Created."
fi

# ---------- Federated Credentials ----------

echo ""
echo "==> [Azure] Setting up Federated Credentials"

add_federated_credential() {
  local NAME="$1"
  local SUBJECT="$2"
  local DESCRIPTION="$3"

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

# GitHub Actions environment — covers all branches and pull requests that run
# jobs with 'environment: default'. Azure does not support wildcard subjects
# that span multiple colon-separated segments, so an environment credential is
# the cleanest way to trust any branch without per-branch credentials.
add_federated_credential \
  "GHA-Default-Creds" \
  "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:default" \
  "GitHub Actions — default environment (all branches)"

# ---------- RBAC assignments (service principal) ----------

echo ""
echo "==> [Azure] Applying RBAC assignments for service principal"
"${SCRIPT_DIR}/apply-azure-rbac.sh" "${APP_ID}" "${SCRIPT_DIR}/../iam/azure-permissions.json"

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
echo "    Set the following GitHub Actions Variables:"
echo "    AZURE_CLIENT_ID       = ${APP_ID}"
echo "    AZURE_TENANT_ID       = ${AZ_TENANT}"
echo "    AZURE_SUBSCRIPTION_ID = ${AZ_SUBSCRIPTION}"
