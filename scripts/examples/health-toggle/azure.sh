#!/usr/bin/env bash
# Demonstrates platform-driven self-healing on Azure Container Apps.
# Liveness probe period ~10s — replica is restarted on probe failure.
# Expect recovery in ~60-90s.
#
# Usage: ./scripts/examples/health-toggle/azure.sh [SOAK_SECONDS]
#   SOAK_SECONDS — baseline traffic before toggling DOWN (default 30)
#
# Requires: az CLI, curl, jq

SOAK="${1:-30}"
POLL_TIMEOUT=180

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

discover_url() {
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
}

toggle_hints() {
  echo "${CYN}    Container Apps liveness probe checks /actuator/health periodically.${RST}"
  echo "${CYN}    On probe failure the replica is restarted — new replica starts healthy.${RST}"
  echo "${CYN}    Watch: Azure Portal → Monitor → Alerts → tf-public-cloud-app-5xx-alert${RST}"
  echo "${CYN}           Container Apps → tf-public-cloud-app → Metrics → Requests by status${RST}"
}

recovery_msg() {
  echo "${GRN}${BLD}==> Recovery confirmed — Container Apps restarted the replica, new instance is healthy${RST}"
}

fetch_logs() {
  local log_start
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
      local workspace
      workspace=$(az monitor log-analytics workspace list \
        --resource-group "${RG}" \
        --query '[0].customerId' --output tsv 2>/dev/null || echo "")
      if [ -n "${workspace}" ]; then
        az monitor log-analytics query \
          --workspace "${workspace}" \
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
}

run_demo
