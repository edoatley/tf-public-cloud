#!/usr/bin/env bash
# Load test and validation script for containerised-app-prod on AWS.
# Prerequisites: aws cli, curl, jq
# Usage: ./aws.sh [--profile <name>] [--hostname <fqdn>]
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
PROFILE="${AWS_PROFILE:-sandbox}"
REGION="eu-west-2"
HOSTNAME="fargate-test.edoatley.co.uk"
BASE_URL="https://${HOSTNAME}"
LOG_GROUP="/ecs/tf-public-cloud-app-prod"
ALB_NAME="tf-public-cloud-app-prod-alb"
TPS=5
DURATION=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)  PROFILE="$2";  shift 2 ;;
    --hostname) HOSTNAME="$2"; BASE_URL="https://${HOSTNAME}"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

PASS=0; FAIL=0

pass() { echo "  PASS: $*"; ((PASS++)); }
fail() { echo "  FAIL: $*"; ((FAIL++)); }

# ── 1. Resolve ALB DNS (sanity check) ────────────────────────────────────────
echo "=== 1. ALB lookup ==="
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names "${ALB_NAME}" \
  --region "${REGION}" \
  --profile "${PROFILE}" \
  --query 'LoadBalancers[0].DNSName' \
  --output text)
echo "  ALB DNS : ${ALB_DNS}"
echo "  TLS host: ${HOSTNAME}"

# ── 2. Health check ───────────────────────────────────────────────────────────
echo ""
echo "=== 2. Health check ==="
HEALTH_BODY=$(curl -sf "${BASE_URL}/actuator/health")
STATUS=$(echo "${HEALTH_BODY}" | jq -r '.status')
if [[ "${STATUS}" == "UP" ]]; then
  pass "health endpoint returned UP"
else
  fail "health endpoint returned: ${STATUS}"
  echo "  Body: ${HEALTH_BODY}"
  exit 1
fi

# ── 3. Items API smoke test ───────────────────────────────────────────────────
echo ""
echo "=== 3. Items API smoke test ==="
ITEMS=$(curl -sf "${BASE_URL}/api/items")
COUNT=$(echo "${ITEMS}" | jq 'length')
if [[ "${COUNT}" -gt 0 ]]; then
  pass "GET /api/items returned ${COUNT} items"
else
  fail "GET /api/items returned no items"
fi

FIRST_ID=$(echo "${ITEMS}" | jq -r '.[0].id')
ITEM=$(curl -sf "${BASE_URL}/api/items/${FIRST_ID}")
NAME=$(echo "${ITEM}" | jq -r '.name')
if [[ -n "${NAME}" ]]; then
  pass "GET /api/items/${FIRST_ID} returned item: ${NAME}"
else
  fail "GET /api/items/${FIRST_ID} returned no name"
fi

# ── 4. Load: 5 TPS for 30s ───────────────────────────────────────────────────
echo ""
echo "=== 4. Load test: ${TPS} TPS for ${DURATION}s ==="
END=$((SECONDS + DURATION))
HTTP_200=0; HTTP_OTHER=0
while [[ $SECONDS -lt $END ]]; do
  for _ in $(seq 1 "${TPS}"); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/items")
    if [[ "${CODE}" == "200" ]]; then
      ((HTTP_200++))
    else
      ((HTTP_OTHER++))
      echo "  unexpected HTTP ${CODE}"
    fi
  done
  sleep 1
done
TOTAL=$((HTTP_200 + HTTP_OTHER))
echo "  Total requests : ${TOTAL}"
echo "  HTTP 200       : ${HTTP_200}"
echo "  Other          : ${HTTP_OTHER}"
if [[ "${HTTP_OTHER}" -eq 0 ]]; then
  pass "all ${TOTAL} requests returned 200"
else
  fail "${HTTP_OTHER}/${TOTAL} requests returned non-200"
fi

# ── 5. 404 error path ────────────────────────────────────────────────────────
echo ""
echo "=== 5. Force 404 ==="
CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/items/99999")
if [[ "${CODE}" == "404" ]]; then
  pass "GET /api/items/99999 correctly returned 404"
else
  fail "GET /api/items/99999 returned ${CODE} (expected 404)"
fi

# ── 6. Health toggle: drive unhealthy → ALB 503 ──────────────────────────────
echo ""
echo "=== 6. Health toggle (DOWN → 503 → UP → recovery) ==="
TOGGLE=$(curl -sf -X POST "${BASE_URL}/health/toggle")
echo "  Toggle response: $(echo "${TOGGLE}" | jq -c .)"
echo "  Waiting 15s for ALB health checks to detect unhealthy state..."
sleep 15

CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/items")
echo "  Response during unhealthy period: HTTP ${CODE}"
if [[ "${CODE}" == "503" || "${CODE}" == "502" ]]; then
  pass "ALB returned ${CODE} for unhealthy service"
else
  echo "  NOTE: expected 503/502, got ${CODE} — may need more tasks or longer wait"
fi

echo "  Toggling health back UP..."
TOGGLE=$(curl -sf -X POST "${BASE_URL}/health/toggle")
echo "  Toggle response: $(echo "${TOGGLE}" | jq -c .)"
echo "  Waiting 30s for recovery (2 consecutive successful health checks)..."
sleep 30

STATUS=$(curl -sf "${BASE_URL}/actuator/health" | jq -r '.status')
if [[ "${STATUS}" == "UP" ]]; then
  pass "service recovered: health is UP"
else
  fail "service did not recover: health is ${STATUS}"
fi

# ── 7. CloudWatch log tail ────────────────────────────────────────────────────
echo ""
echo "=== 7. Recent CloudWatch logs (last 5 min) ==="
START_MS=$(( ($(date +%s) - 300) * 1000 ))
aws logs filter-log-events \
  --log-group-name "${LOG_GROUP}" \
  --start-time "${START_MS}" \
  --region "${REGION}" \
  --profile "${PROFILE}" \
  --query 'events[*].message' \
  --output text \
  | head -40 \
  || echo "  (no log events or insufficient permissions)"

# ── 8. ECS service state ──────────────────────────────────────────────────────
echo ""
echo "=== 8. ECS service state ==="
aws ecs describe-services \
  --cluster tf-public-cloud-app-prod \
  --services tf-public-cloud-app-prod \
  --region "${REGION}" \
  --profile "${PROFILE}" \
  --query 'services[0].{running:runningCount,desired:desiredCount,pending:pendingCount,status:status}' \
  --output table

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
echo "  Passed : ${PASS}"
echo "  Failed : ${FAIL}"
echo ""
TOTAL_CHECKS=$((PASS + FAIL))
if [[ "${FAIL}" -eq 0 ]]; then
  echo "All ${TOTAL_CHECKS} checks passed."
else
  echo "${FAIL}/${TOTAL_CHECKS} checks FAILED."
  exit 1
fi
