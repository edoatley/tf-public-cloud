#!/usr/bin/env bash
# Smoke-tests the serverless add function running on Azure Functions.
# Looks up the Function App hostname via the az CLI — no terraform output needed.
# Usage: ./scripts/examples/serverless/azure.sh
set -euo pipefail

FUNCTION_APP_PREFIX="tfpubcloudfn"

echo "==> Looking up Function App hostname"
BASE_URL="https://$(az functionapp list \
  --query "[?starts_with(name, '${FUNCTION_APP_PREFIX}')].defaultHostName | [0]" \
  --output tsv)/api/add"
echo "     ${BASE_URL}"

echo "==> GET ?a=3&b=5 (expect 8)"
RESULT=$(curl -sf --max-time 60 "${BASE_URL}?a=3&b=5" | jq -r '.result')
if [ "${RESULT}" = "8.0" ] || [ "${RESULT}" = "8" ]; then
  echo "     Got expected result: ${RESULT}"
else
  echo "     FAIL: expected 8 but got ${RESULT}" >&2
  exit 1
fi

echo "==> GET ?a=-1&b=1 (expect 0)"
RESULT=$(curl -sf --max-time 60 "${BASE_URL}?a=-1&b=1" | jq -r '.result')
if [ "${RESULT}" = "0.0" ] || [ "${RESULT}" = "0" ]; then
  echo "     Got expected result: ${RESULT}"
else
  echo "     FAIL: expected 0 but got ${RESULT}" >&2
  exit 1
fi

echo "==> GET ?a=bad (expect 400)"
STATUS=$(curl -o /dev/null -sw '%{http_code}' --max-time 60 "${BASE_URL}?a=bad&b=1")
if [ "${STATUS}" = "400" ]; then
  echo "     Got expected 400"
else
  echo "     FAIL: expected 400 but got ${STATUS}" >&2
  exit 1
fi

echo "==> Done"
