#!/usr/bin/env bash
# Smoke-tests the containerised app running on Azure Container Apps.
# Looks up the app FQDN via the az CLI — no terraform output needed.
# Usage: ./scripts/examples/containerised-app-azure.sh
set -euo pipefail

echo "==> Looking up Container App FQDN"
BASE_URL="https://$(az containerapp show \
  --name "tf-public-cloud-app" \
  --query "properties.latestRevisionFqdn" \
  --output tsv \
  --resource-group "$(az containerapp list \
    --query "[?name=='tf-public-cloud-app'].resourceGroup | [0]" \
    --output tsv)")"
echo "     ${BASE_URL}"

echo "==> GET /api/items"
curl -sf "${BASE_URL}/api/items" | jq .

echo "==> GET /api/items/1"
curl -sf "${BASE_URL}/api/items/1" | jq .

echo "==> GET /api/items/99 (expect 404)"
STATUS=$(curl -o /dev/null -sw '%{http_code}' "${BASE_URL}/api/items/99")
if [ "${STATUS}" = "404" ]; then
  echo "     Got expected 404"
else
  echo "     FAIL: expected 404 but got ${STATUS}" >&2
  exit 1
fi

echo "==> GET /actuator/health"
curl -sf "${BASE_URL}/actuator/health" | jq .

echo "==> Done"
