#!/usr/bin/env bash
# Demonstrates platform-driven self-healing on AWS ECS/ALB:
#   1. Runs baseline traffic (all 200s)
#   2. Toggles /actuator/health → DOWN (503s begin)
#   3. Waits for ECS to detect the failure and replace the task (platform-driven, no manual toggle)
#   4. Confirms recovery (200s resume on the fresh task)
#   5. Fetches CloudWatch logs proving the old task stopped and the new one started
#
# Usage: ./scripts/demo/health-toggle-demo-aws.sh [SOAK_SECONDS]
#   SOAK_SECONDS — baseline traffic before toggling DOWN (default 30)
#
# Requires: aws CLI, curl, jq
set -euo pipefail
export AWS_PAGER=""
export AWS_PROFILE="${AWS_PROFILE:-sandbox}"

SOAK="${1:-30}"

# ECS health check: interval=30s, retries=3 → 90s to declare unhealthy
# New task start + ALB registration: ~60s
# Total expected window: ~150-180s — we poll until we actually see 200s
POLL_TIMEOUT=300

# --- colour helpers (no-op when not a TTY) ---
if [ -t 1 ] && command -v tput &>/dev/null; then
  GRN=$(tput setaf 2); YLW=$(tput setaf 3); RED=$(tput setaf 1)
  CYN=$(tput setaf 6); BLD=$(tput bold); RST=$(tput sgr0)
else
  GRN=''; YLW=''; RED=''; CYN=''; BLD=''; RST=''
fi

count_2xx=0; count_4xx=0; count_5xx=0; count_502=0; count_total=0

cleanup() {
  echo ""
  echo "${BLD}=== Summary ===${RST}"
  echo "  Total requests : ${count_total}"
  echo "  ${GRN}2xx${RST}            : ${count_2xx}"
  echo "  ${YLW}4xx${RST}            : ${count_4xx}"
  echo "  ${RED}5xx (503)${RST}      : ${count_5xx}"
  echo "  ${RED}502 (no target)${RST} : ${count_502}"
}
trap cleanup EXIT

hit() {
  local method="$1" path="$2"
  local status
  status=$(curl -o /dev/null -sw '%{http_code}' -X "${method}" "${BASE_URL}${path}")
  count_total=$((count_total + 1))
  local colour
  case "${status}" in
    2*) count_2xx=$((count_2xx + 1));  colour="${GRN}" ;;
    404) count_4xx=$((count_4xx + 1)); colour="${YLW}" ;;
    502) count_502=$((count_502 + 1)); colour="${RED}" ;;
    5*)  count_5xx=$((count_5xx + 1)); colour="${RED}" ;;
    *)   colour="${YLW}" ;;
  esac
  printf "%s[%s]%s %-6s %-30s → %s%s%s\n" \
    "${BLD}" "$(date +%H:%M:%S)" "${RST}" "${method}" "${path}" "${colour}" "${status}" "${RST}"
}

traffic_loop() {
  local end_at=$(( $(date +%s) + $1 ))
  while [ "$(date +%s)" -lt "${end_at}" ]; do
    hit GET /api/items
    sleep 0.5
    hit GET /api/items/1
    sleep 0.5
    hit GET /api/items/99
    sleep 0.5
    hit GET /actuator/health
    sleep 0.5
  done
}

# --- URL discovery ---
echo "${BLD}==> Looking up ALB DNS name${RST}"
BASE_URL="http://$(aws elbv2 describe-load-balancers \
  --names "tf-public-cloud-app-alb" \
  --query 'LoadBalancers[0].DNSName' \
  --output text)"
echo "    ${BASE_URL}"

# --- Phase 1: baseline ---
echo ""
echo "${BLD}==> Phase 1: baseline traffic for ${SOAK}s — all requests should be 200/404${RST}"
traffic_loop "${SOAK}"

# --- Toggle DOWN ---
toggle_time=$(date +%s)
echo ""
echo "${RED}${BLD}==> Toggling health → DOWN${RST}"
echo "${CYN}    ECS will run its health check every 30s — after 3 failures (~90s) it will${RST}"
echo "${CYN}    stop this task and start a replacement. The new task starts with health UP.${RST}"
echo "${CYN}    Watch: ECS → Clusters → tf-public-cloud-app → Services → Events tab${RST}"
echo "${CYN}           CloudWatch → Alarms → tf-public-cloud-app-target-5xx${RST}"
curl -s -X POST "${BASE_URL}/health/toggle" | jq .
echo ""

# --- Phase 2: poll until platform-driven recovery ---
echo "${BLD}==> Phase 2: waiting for ECS to replace the task (no manual toggle — platform drives this)${RST}"
echo "${BLD}    503 = app reporting DOWN, 502 = ALB has no healthy target (task being replaced)${RST}"
echo ""

recovery_time=""
deadline=$(( toggle_time + POLL_TIMEOUT ))
consecutive_200s=0

while [ "$(date +%s)" -lt "${deadline}" ]; do
  hit GET /api/items
  sleep 0.5
  hit GET /api/items/1
  sleep 0.5
  hit GET /api/items/99
  sleep 0.5
  status=$(curl -o /dev/null -sw '%{http_code}' "${BASE_URL}/actuator/health")
  count_total=$((count_total + 1))
  if [ "${status}" = "200" ]; then
    count_2xx=$((count_2xx + 1))
    consecutive_200s=$((consecutive_200s + 1))
    printf "%s[%s]%s %-6s %-30s → %s%s%s\n" \
      "${BLD}" "$(date +%H:%M:%S)" "${RST}" "GET" "/actuator/health" "${GRN}" "${status}" "${RST}"
    if [ "${consecutive_200s}" -ge 3 ]; then
      recovery_time=$(date +%s)
      echo ""
      echo "${GRN}${BLD}==> Recovery confirmed — new ECS task is healthy and serving traffic${RST}"
      echo "${GRN}    Time from toggle to recovery: $(( recovery_time - toggle_time ))s${RST}"
      break
    fi
  else
    consecutive_200s=0
    case "${status}" in
      502) count_502=$((count_502 + 1)); colour="${RED}" ;;
      5*)  count_5xx=$((count_5xx + 1)); colour="${RED}" ;;
      *)   colour="${YLW}" ;;
    esac
    printf "%s[%s]%s %-6s %-30s → %s%s%s\n" \
      "${BLD}" "$(date +%H:%M:%S)" "${RST}" "GET" "/actuator/health" "${colour}" "${status}" "${RST}"
  fi
  sleep 0.5
done

if [ -z "${recovery_time}" ]; then
  echo "${RED}${BLD}==> Timed out after ${POLL_TIMEOUT}s waiting for recovery — check ECS console${RST}"
  exit 1
fi

# --- Phase 3: post-recovery soak ---
echo ""
echo "${BLD}==> Phase 3: post-recovery traffic for 30s — confirming stable 200s on new task${RST}"
traffic_loop 30

# --- Fetch logs proving task replacement ---
echo ""
echo "${CYN}${BLD}==> Fetching CloudWatch logs around the task replacement window${RST}"
echo "${CYN}    Log group: /ecs/tf-public-cloud-app${RST}"
echo ""

# Window: from 60s before toggle to now
log_start_ms=$(( (toggle_time - 60) * 1000 ))
log_end_ms=$(( $(date +%s) * 1000 ))

aws logs filter-log-events \
  --log-group-name "/ecs/tf-public-cloud-app" \
  --start-time "${log_start_ms}" \
  --end-time "${log_end_ms}" \
  --filter-pattern "" \
  --query 'events[*].[timestamp,message]' \
  --output text \
| while IFS=$'\t' read -r ts msg; do
    human=$(date -r $(( ts / 1000 )) '+%H:%M:%S' 2>/dev/null \
         || date -d "@$(( ts / 1000 ))" '+%H:%M:%S' 2>/dev/null \
         || echo "${ts}")
    printf "%s[%s]%s %s\n" "${CYN}" "${human}" "${RST}" "${msg}"
  done

echo ""
echo "${GRN}${BLD}==> Demo complete${RST}"
echo "${GRN}    The logs above show the old task stopping and the new task starting.${RST}"
echo "${GRN}    Key lines to look for: Spring Boot startup banner on the new task,${RST}"
echo "${GRN}    and the absence of any lines after the toggle on the old task.${RST}"
