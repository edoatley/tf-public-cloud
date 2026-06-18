#!/usr/bin/env bash
# Demonstrates platform-driven self-healing on AWS ECS/ALB.
# ECS health check: interval=30s, retries=3 → ~90s to declare unhealthy.
# New task start + ALB registration adds ~60s → expect recovery in ~150-180s.
#
# Usage: ./scripts/examples/health-toggle/aws.sh [SOAK_SECONDS]
#   SOAK_SECONDS — baseline traffic before toggling DOWN (default 30)
#
# Requires: aws CLI, curl, jq
export AWS_PAGER=""
export AWS_PROFILE="${AWS_PROFILE:-sandbox}"

SOAK="${1:-30}"
POLL_TIMEOUT=300

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

discover_url() {
  echo "${BLD}==> Looking up ALB DNS name${RST}"
  BASE_URL="http://$(aws elbv2 describe-load-balancers \
    --names "tf-public-cloud-app-alb" \
    --query 'LoadBalancers[0].DNSName' \
    --output text)"
  echo "    ${BASE_URL}"
}

toggle_hints() {
  echo "${CYN}    ECS health check runs every 30s — after 3 failures (~90s) ECS stops${RST}"
  echo "${CYN}    this task and starts a replacement. The new task starts with health UP.${RST}"
  echo "${CYN}    Watch: ECS → Clusters → tf-public-cloud-app → Services → Events tab${RST}"
  echo "${CYN}           CloudWatch → Alarms → tf-public-cloud-app-target-5xx${RST}"
}

recovery_msg() {
  echo "${GRN}${BLD}==> Recovery confirmed — new ECS task is healthy and serving traffic${RST}"
}

fetch_logs() {
  echo "${CYN}    Log group: /ecs/tf-public-cloud-app${RST}"
  echo ""
  local log_start_ms log_end_ms
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
}

run_demo
