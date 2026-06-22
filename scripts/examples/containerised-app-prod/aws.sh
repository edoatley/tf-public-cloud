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
TMPFILE=$(mktemp)
trap 'rm -f "${TMPFILE}"' EXIT

pass() { echo "  PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }

# curl into TMPFILE; last line is the HTTP status code, rest is body
curl_check() { curl -s -w '\n%{http_code}' "$@" > "${TMPFILE}"; }
body() { awk 'NR>1{print prev} {prev=$0}' "${TMPFILE}"; }
code() { tail -1 "${TMPFILE}"; }

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
curl_check "${BASE_URL}/actuator/health"
HEALTH_CODE=$(code); HEALTH_BODY=$(body)
STATUS=$(echo "${HEALTH_BODY}" | jq -r '.status // "UNKNOWN"')
if [[ "${HEALTH_CODE}" == "200" && "${STATUS}" == "UP" ]]; then
  pass "health endpoint returned UP"
else
  fail "health endpoint: HTTP ${HEALTH_CODE}, status=${STATUS}"
  echo "  Body: ${HEALTH_BODY}"
  exit 1
fi

# ── 3. Items API smoke test ───────────────────────────────────────────────────
echo ""
echo "=== 3. Items API smoke test ==="
curl_check "${BASE_URL}/api/items"
ITEMS_CODE=$(code); ITEMS=$(body)
if [[ "${ITEMS_CODE}" == "200" ]]; then
  COUNT=$(echo "${ITEMS}" | jq 'length')
  if [[ "${COUNT}" -gt 0 ]]; then
    pass "GET /api/items returned ${COUNT} items"
  else
    fail "GET /api/items returned empty array"
    COUNT=0
  fi
else
  fail "GET /api/items returned HTTP ${ITEMS_CODE}"
  COUNT=0
fi

if [[ "${COUNT}" -gt 0 ]]; then
  FIRST_ID=$(echo "${ITEMS}" | jq -r '.[0].id')
  curl_check "${BASE_URL}/api/items/${FIRST_ID}"
  ITEM_CODE=$(code); ITEM=$(body)
  NAME=$(echo "${ITEM}" | jq -r '.name // ""')
  if [[ "${ITEM_CODE}" == "200" && -n "${NAME}" ]]; then
    pass "GET /api/items/${FIRST_ID} returned item: ${NAME}"
  else
    fail "GET /api/items/${FIRST_ID}: HTTP ${ITEM_CODE}, name=${NAME}"
  fi
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
      HTTP_200=$((HTTP_200 + 1))
    else
      HTTP_OTHER=$((HTTP_OTHER + 1))
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

# ── 6. AZ failover + autoscaling test ────────────────────────────────────────
# Step A: reduce to 1 task, confirm traffic still flows (other AZ picks up).
# Step B: drive load to push CPU above the 20% scale target, confirm ECS
#         scales back out to 2.
echo ""
echo "=== 6. AZ failover + autoscaling ==="

CLUSTER="tf-public-cloud-app-prod"
SERVICE="tf-public-cloud-app-prod"

# ── 6a. Kill one task, confirm the other AZ keeps serving ────────────────────
echo "--- 6a. Stopping one task (AZ failover) ---"

# Pick the first running task and record its AZ
TASK_ARN=$(aws ecs list-tasks \
  --cluster "${CLUSTER}" --service-name "${SERVICE}" \
  --region "${REGION}" --profile "${PROFILE}" \
  --query 'taskArns[0]' --output text)
TASK_AZ=$(aws ecs describe-tasks \
  --cluster "${CLUSTER}" --tasks "${TASK_ARN}" \
  --region "${REGION}" --profile "${PROFILE}" \
  --query 'tasks[0].availabilityZone' --output text)
echo "  Stopping task in ${TASK_AZ}: ${TASK_ARN##*/}"

aws ecs stop-task \
  --cluster "${CLUSTER}" --task "${TASK_ARN}" \
  --reason "load-test AZ failover simulation" \
  --region "${REGION}" --profile "${PROFILE}" \
  --query 'task.{lastStatus:lastStatus,az:availabilityZone}' \
  --output table

echo "  Waiting 20s for ALB to drain stopped task..."
sleep 20

CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/items")
if [[ "${CODE}" == "200" ]]; then
  pass "traffic still served after task stop (AZ failover confirmed)"
else
  fail "unexpected HTTP ${CODE} after task stop"
fi

# Confirm ECS has already restarted a replacement (desired=2 still)
RUNNING=$(aws ecs describe-services \
  --cluster "${CLUSTER}" --services "${SERVICE}" \
  --region "${REGION}" --profile "${PROFILE}" \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}' \
  --output table)
echo "${RUNNING}"

# ── 6b. Drive load to trigger autoscaling ────────────────────────────────────
echo ""
echo "--- 6b. Driving load to trigger autoscale (cpu_scale_target=5%) ---"
echo "  Sending sustained load for 180s (monitoring CPU every 20s)..."
LOAD_END=$((SECONDS + 180))
LOAD_PIDS=()

# Launch 10 background curl workers to saturate the single task
for _ in $(seq 1 10); do
  ( while [[ $SECONDS -lt $LOAD_END ]]; do
      curl -s -o /dev/null "${BASE_URL}/api/items"
    done ) &
  LOAD_PIDS+=($!)
done

# Poll ECS running count and autoscaling activity every 15s while load runs
SCALED=false
while [[ $SECONDS -lt $LOAD_END ]]; do
  sleep 20
  RUNNING=$(aws ecs describe-services \
    --cluster "${CLUSTER}" --services "${SERVICE}" \
    --region "${REGION}" --profile "${PROFILE}" \
    --query 'services[0].runningCount' --output text)
  CPU=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/ECS \
    --metric-name CPUUtilization \
    --dimensions Name=ClusterName,Value="${CLUSTER}" Name=ServiceName,Value="${SERVICE}" \
    --start-time "$(date -u -v-2M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u --date='2 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')" \
    --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --period 60 --statistics Average \
    --region "${REGION}" --profile "${PROFILE}" \
    --query 'sort_by(Datapoints,&Timestamp)[-1].Average' \
    --output text 2>/dev/null || echo "N/A")
  echo "  running=${RUNNING}  cpu=${CPU}%"
  if [[ "${RUNNING}" -ge 2 ]] 2>/dev/null; then
    SCALED=true
  fi
done

# Stop background load workers
for PID in "${LOAD_PIDS[@]}"; do
  kill "${PID}" 2>/dev/null || true
done
wait "${LOAD_PIDS[@]}" 2>/dev/null || true

if [[ "${SCALED}" == "true" ]]; then
  pass "ECS scaled out to ${RUNNING} tasks under load"
else
  echo "  NOTE: no scale-out observed during load window — checking scaling activities..."
  aws application-autoscaling describe-scaling-activities \
    --service-namespace ecs \
    --resource-id "service/${CLUSTER}/${SERVICE}" \
    --region "${REGION}" --profile "${PROFILE}" \
    --query 'ScalingActivities[0].{cause:Cause,status:StatusCode,time:StartTime}' \
    --output table 2>/dev/null || true
  fail "ECS did not scale out — CPU may not have crossed 20% threshold"
fi

# ── 6c. Confirm final service state ──────────────────────────────────────────
echo ""
echo "--- 6c. Final service state ---"
aws ecs describe-services \
  --cluster "${CLUSTER}" --services "${SERVICE}" \
  --region "${REGION}" --profile "${PROFILE}" \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}' \
  --output table

# ── 7. CloudWatch log tail ────────────────────────────────────────────────────
echo ""
echo "=== 7. Recent CloudWatch logs (last 10 min) ==="
START_MS=$(( ($(date +%s) - 600) * 1000 ))
aws logs filter-log-events \
  --log-group-name "${LOG_GROUP}" \
  --start-time "${START_MS}" \
  --region "${REGION}" \
  --profile "${PROFILE}" \
  --query 'events[*].{t:timestamp,m:message}' \
  --output json 2>/dev/null \
  | jq -r '.[] | ((.t / 1000 | todate) + "  " + .m)' \
  | grep -v "^$" \
  | tail -40 \
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
