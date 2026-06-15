#!/usr/bin/env bash
# Smoke-tests the serverless add function running on GCP Cloud Functions v2.
# Looks up the function URL via the gcloud CLI — no terraform output needed.
# Usage: ./scripts/examples/serverless-gcp.sh [project-id]
set -euo pipefail

PROJECT="${1:-$(gcloud config get-value project 2>/dev/null)}"
: "${PROJECT:?Pass a project ID or set a default with: gcloud config set project PROJECT_ID}"

FUNCTION_NAME="tf-public-cloud-add"
REGION="europe-west1"

echo "==> Looking up Cloud Function URL"
BASE_URL="$(gcloud functions describe "${FUNCTION_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT}" \
  --format 'value(serviceConfig.uri)')"
echo "     ${BASE_URL}"

echo "==> GET ?a=3&b=5 (expect 8)"
RESULT=$(curl -sf "${BASE_URL}?a=3&b=5" | jq -r '.result')
if [ "${RESULT}" = "8.0" ] || [ "${RESULT}" = "8" ]; then
  echo "     Got expected result: ${RESULT}"
else
  echo "     FAIL: expected 8 but got ${RESULT}" >&2
  exit 1
fi

echo "==> GET ?a=-1&b=1 (expect 0)"
RESULT=$(curl -sf "${BASE_URL}?a=-1&b=1" | jq -r '.result')
if [ "${RESULT}" = "0.0" ] || [ "${RESULT}" = "0" ]; then
  echo "     Got expected result: ${RESULT}"
else
  echo "     FAIL: expected 0 but got ${RESULT}" >&2
  exit 1
fi

echo "==> GET ?a=bad (expect 400)"
STATUS=$(curl -o /dev/null -sw '%{http_code}' "${BASE_URL}?a=bad&b=1")
if [ "${STATUS}" = "400" ]; then
  echo "     Got expected 400"
else
  echo "     FAIL: expected 400 but got ${STATUS}" >&2
  exit 1
fi

echo "==> Done"
