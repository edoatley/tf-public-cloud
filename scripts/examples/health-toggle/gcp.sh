#!/usr/bin/env bash
# Demonstrates platform-driven self-healing on GCP Cloud Run.
# Liveness probe period=10s — a single failed probe triggers an immediate container restart.
# Expect recovery in ~30-60s.
#
# Usage: ./scripts/examples/health-toggle/gcp.sh [PROJECT_ID] [SOAK_SECONDS]
#   PROJECT_ID   — GCP project (default: gcloud config get-value project)
#   SOAK_SECONDS — baseline traffic before toggling DOWN (default 30)
#
# Requires: gcloud CLI, curl, jq

PROJECT="${1:-$(gcloud config get-value project 2>/dev/null)}"
: "${PROJECT:?Pass a project ID or set a default with: gcloud config set project PROJECT_ID}"
SOAK="${2:-30}"
POLL_TIMEOUT=180

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

discover_url() {
  echo "${BLD}==> Looking up Cloud Run service URL${RST}"
  BASE_URL="$(gcloud run services describe tf-public-cloud-app \
    --region europe-west1 \
    --project "${PROJECT}" \
    --format 'value(status.url)')"
  echo "    ${BASE_URL}"
}

toggle_hints() {
  echo "${CYN}    Cloud Run liveness probe checks /actuator/health every 10s.${RST}"
  echo "${CYN}    On the next failed probe Cloud Run restarts the container immediately.${RST}"
  echo "${CYN}    The new container starts with health UP — no manual toggle needed.${RST}"
  echo "${CYN}    Watch: Cloud Run → tf-public-cloud-app → Revisions (restart count)${RST}"
  echo "${CYN}           Monitoring → Alerting → tf-public-cloud-app Cloud Run 5xx errors${RST}"
}

recovery_msg() {
  echo "${GRN}${BLD}==> Recovery confirmed — Cloud Run restarted the container, new instance is healthy${RST}"
}

fetch_logs() {
  local log_start log_end
  log_start=$(date -u -r $(( toggle_time - 60 )) '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
           || date -u -d "@$(( toggle_time - 60 ))" '+%Y-%m-%dT%H:%M:%SZ')
  log_end=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  gcloud logging read \
    "resource.type=\"cloud_run_revision\"
     resource.labels.service_name=\"tf-public-cloud-app\"
     timestamp>=\"${log_start}\"
     timestamp<=\"${log_end}\"" \
    --project "${PROJECT}" \
    --limit 50 \
    --format "value(timestamp,textPayload,jsonPayload.message)" \
    --order asc \
  | grep -v '^$' \
  | while IFS= read -r line; do
      printf "%s%s%s\n" "${CYN}" "${line}" "${RST}"
    done
}

run_demo
