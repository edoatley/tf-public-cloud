#!/usr/bin/env bash
# Demonstrates the health toggle, liveness probe restart, and Cloud Monitoring alert on GCP Cloud Run.
#
# Usage: ./scripts/demo/health-toggle-demo-gcp.sh [PROJECT_ID] [SOAK_SECONDS] [DOWN_SECONDS] [RECOVERY_SECONDS]
#   PROJECT_ID       — GCP project (default: gcloud config get-value project)
#   SOAK_SECONDS     — traffic before toggling DOWN  (default 30)
#   DOWN_SECONDS     — time spent DOWN before toggling UP (default 60)
#   RECOVERY_SECONDS — traffic after recovery before exit (default 30)
#
# Requires: gcloud CLI, curl, jq
set -euo pipefail

PROJECT="${1:-$(gcloud config get-value project 2>/dev/null)}"
: "${PROJECT:?Pass a project ID or set a default with: gcloud config set project PROJECT_ID}"
SOAK="${2:-30}"
DOWN="${3:-60}"
RECOVERY="${4:-30}"

# --- colour helpers (no-op when not a TTY) ---
if [ -t 1 ] && command -v tput &>/dev/null; then
  GRN=$(tput setaf 2); YLW=$(tput setaf 3); RED=$(tput setaf 1)
  BLD=$(tput bold); RST=$(tput sgr0)
else
  GRN=''; YLW=''; RED=''; BLD=''; RST=''
fi

count_2xx=0; count_4xx=0; count_5xx=0; count_total=0

cleanup() {
  echo ""
  echo "${BLD}=== Summary ===${RST}"
  echo "  Total requests : ${count_total}"
  echo "  ${GRN}2xx${RST}            : ${count_2xx}"
  echo "  ${YLW}4xx${RST}            : ${count_4xx}"
  echo "  ${RED}5xx${RST}            : ${count_5xx}"
}
trap cleanup EXIT

hit() {
  local method="$1" path="$2"
  local status
  status=$(curl -o /dev/null -sw '%{http_code}' -X "${method}" "${BASE_URL}${path}")
  count_total=$((count_total + 1))
  local colour="${GRN}"
  case "${status:0:1}" in
    2) count_2xx=$((count_2xx + 1)); colour="${GRN}" ;;
    4) count_4xx=$((count_4xx + 1)); colour="${YLW}" ;;
    5) count_5xx=$((count_5xx + 1)); colour="${RED}" ;;
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
echo "${BLD}==> Looking up Cloud Run service URL${RST}"
BASE_URL="$(gcloud run services describe tf-public-cloud-app \
  --region europe-west1 \
  --project "${PROJECT}" \
  --format 'value(status.url)')"
echo "    ${BASE_URL}"

# --- Phase 1: soak ---
echo ""
echo "${BLD}==> Phase 1: baseline traffic for ${SOAK}s${RST}"
traffic_loop "${SOAK}"

# --- Toggle DOWN ---
echo ""
echo "${RED}${BLD}==> Toggling health → DOWN (liveness probe will fail → Cloud Run restarts revision)${RST}"
echo "${RED}${BLD}    Watch: Cloud Console → Monitoring → Alerting → tf-public-cloud-app Cloud Run 5xx errors${RST}"
echo "${RED}${BLD}           Cloud Run → tf-public-cloud-app → Revisions (restart count)${RST}"
curl -s -X POST "${BASE_URL}/health/toggle" | jq .
echo ""

# --- Phase 2: down ---
echo "${BLD}==> Phase 2: traffic while DOWN for ${DOWN}s — expect 503s${RST}"
traffic_loop "${DOWN}"

# --- Toggle UP ---
echo ""
echo "${GRN}${BLD}==> Toggling health → UP (instance recovers)${RST}"
curl -s -X POST "${BASE_URL}/health/toggle" | jq .
echo ""

# --- Phase 3: recovery ---
echo "${BLD}==> Phase 3: recovery traffic for ${RECOVERY}s — 503s should stop${RST}"
traffic_loop "${RECOVERY}"

echo ""
echo "${GRN}${BLD}==> Demo complete${RST}"
