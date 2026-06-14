#!/usr/bin/env bash
# Smoke-tests the containerised app running on GCP Cloud Run.
# Looks up the service URL via the gcloud CLI — no terraform output needed.
# Usage: ./scripts/examples/containerised-app-gcp.sh [project-id]
set -euo pipefail

PROJECT="${1:-$(gcloud config get-value project 2>/dev/null)}"
: "${PROJECT:?Pass a project ID or set a default with: gcloud config set project PROJECT_ID}"

echo "==> Looking up Cloud Run service URL"
BASE_URL="$(gcloud run services describe tf-public-cloud-app \
  --region europe-west1 \
  --project "${PROJECT}" \
  --format 'value(status.url)')"
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
