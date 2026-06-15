#!/usr/bin/env bash
# Demonstrates platform-driven self-healing on Azure Container Apps:
#   1. Runs baseline traffic (all 200s)
#   2. Toggles /actuator/health → DOWN (503s begin)
#   3. Waits for Container Apps to detect the liveness probe failure and restart the replica
#   4. Confirms recovery (200s resume on the fresh replica)
#   5. Fetches container logs proving the replica was restarted
#
# Usage: ./scripts/demo/health-toggle-demo-azure.sh [SOAK_SECONDS]
#   SOAK_SECONDS — baseline traffic before toggling DOWN (default 30)
#
# Requires: az CLI, curl, jq
set -euo pipefail

SOAK="${1:-30}"

# Container Apps liveness probe: default period ~10s
# Replica restart typically completes within 30-60s
POLL_TIMEOUT=180

# --- colour helpers (no-op when not a TTY) ---
if [ -t 1 ] && command -v tput &>/dev/null; then
  GRN=$(tput setaf 2); YLW=$(tput setaf 3); RED=$(tput setaf 1)
  CYN=$(tput setaf 6); BLD=$(tput bold); RST=$(tput sgr0)
else
  GRN=''; YLW=''; RED=''; CYN=''; BLD=''; RST=''
fi

count_2xx=0; count_4xx=0; count_5xx=0; count_total=0

cleanup() {
  echo ""
  echo "${BLD}=== Summary ===${RST}"
  echo "  Total requests : ${count_total}"
  echo "  ${GRN}2xx${RST}            : ${count_2xx}"
  echo "  ${YLW}4xx${RST}            : ${count_4xx}"
  echo "  ${RED}5xx (503)${RST}      : ${count_5xx}"
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
echo "${BLD}==> Looking up Container App FQDN${RST}"
RG=$(az containerapp list \
  --query "[?name=='tf-public-cloud-app'].resourceGroup | [0]" \
  --output tsv)
BASE_URL="https://$(az containerapp show \
  --name "tf-public-cloud-app" \
  --resource-group "${RG}" \
  --query "properties.latestRevisionFqdn" \
  --output tsv)"
echo "    ${BASE_URL}"

# --- Phase 1: baseline ---
echo ""
echo "${BLD}==> Phase 1: baseline traffic for ${SOAK}s — all requests should be 200/404${RST}"
traffic_loop "${SOAK}"

# --- Toggle DOWN ---
toggle_time=$(date +%s)
echo ""
echo "${RED}${BLD}==> Toggling health → DOWN${RST}"
echo "${CYN}    Container Apps liveness probe checks /actuator/health periodically.${RST}"
echo "${CYN}    On probe failure it will restart the replica — the new replica starts healthy.${RST}"
echo "${CYN}    Watch: Azure Portal → Monitor → Alerts → tf-public-cloud-app-5xx-alert${RST}"
echo "${CYN}           Container Apps → tf-public-cloud-app → Metrics → Requests by status${RST}"
curl -s -X POST "${BASE_URL}/health/toggle" | jq .
echo ""

# --- Phase 2: poll until platform-driven recovery ---
echo "${BLD}==> Phase 2: waiting for Container Apps to restart the replica (platform-driven)${RST}"
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
      echo "${GRN}${BLD}==> Recovery confirmed — Container Apps restarted the replica, new instance is healthy${RST}"
      echo "${GRN}    Time from toggle to recovery: $(( recovery_time - toggle_time ))s${RST}"
      break
    fi
  else
    consecutive_200s=0
    count_5xx=$((count_5xx + 1))
    printf "%s[%s]%s %-6s %-30s → %s%s%s\n" \
      "${BLD}" "$(date +%H:%M:%S)" "${RST}" "GET" "/actuator/health" "${RED}" "${status}" "${RST}"
  fi
  sleep 0.5
done

if [ -z "${recovery_time}" ]; then
  echo "${RED}${BLD}==> Timed out after ${POLL_TIMEOUT}s waiting for recovery — check Container Apps console${RST}"
  exit 1
fi

# --- Phase 3: post-recovery soak ---
echo ""
echo "${BLD}==> Phase 3: post-recovery traffic for 30s — confirming stable 200s on new replica${RST}"
traffic_loop 30

# --- Fetch logs proving replica restart ---
echo ""
echo "${CYN}${BLD}==> Fetching container logs around the restart window${RST}"
echo ""

# ISO8601 window: 60s before toggle to now
log_start=$(date -u -r $(( toggle_time - 60 )) '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
         || date -u -d "@$(( toggle_time - 60 ))" '+%Y-%m-%dT%H:%M:%SZ')

az containerapp logs show \
  --name "tf-public-cloud-app" \
  --resource-group "${RG}" \
  --tail 100 \
  --follow false \
  2>/dev/null \
| while IFS= read -r line; do
    printf "%s%s%s\n" "${CYN}" "${line}" "${RST}"
  done || {
    echo "${CYN}Live log stream unavailable — fetching via Log Analytics instead:${RST}"
    WORKSPACE=$(az monitor log-analytics workspace list \
      --resource-group "${RG}" \
      --query '[0].customerId' --output tsv 2>/dev/null || echo "")
    if [ -n "${WORKSPACE}" ]; then
      az monitor log-analytics query \
        --workspace "${WORKSPACE}" \
        --analytics-query "ContainerAppConsoleLogs
          | where ContainerAppName == 'tf-public-cloud-app'
          | where TimeGenerated >= datetime('${log_start}')
          | order by TimeGenerated asc
          | project TimeGenerated, Log" \
        --output table 2>/dev/null \
      | while IFS= read -r line; do
          printf "%s%s%s\n" "${CYN}" "${line}" "${RST}"
        done
    else
      echo "${YLW}No Log Analytics workspace found — view logs in Azure Portal:${RST}"
      echo "${YLW}Container Apps → tf-public-cloud-app → Log stream${RST}"
    fi
  }

echo ""
echo "${GRN}${BLD}==> Demo complete${RST}"
echo "${GRN}    Look for Spring Boot startup banner in the logs above — that is the new replica.${RST}"
echo "${GRN}    The gap in log timestamps around the toggle confirms the old replica was stopped.${RST}"
