#!/usr/bin/env bash
# Shared library for health-toggle demo scripts. Source this file, then implement:
#   discover_url   — set BASE_URL and print the discovered address
#   toggle_hints   — print cloud-specific "watch here" guidance
#   recovery_msg   — print cloud-specific recovery confirmation message
#   fetch_logs     — fetch and print logs proving the instance was replaced
#
# Caller must also set before sourcing:
#   POLL_TIMEOUT   — seconds to wait for platform-driven recovery
#   SOAK           — baseline traffic duration in seconds

set -euo pipefail

# --- colour helpers (no-op when not a TTY) ---
if [ -t 1 ] && command -v tput &>/dev/null; then
  GRN=$(tput setaf 2); YLW=$(tput setaf 3); RED=$(tput setaf 1)
  CYN=$(tput setaf 6); BLD=$(tput bold); RST=$(tput sgr0)
else
  GRN=''; YLW=''; RED=''; CYN=''; BLD=''; RST=''
fi

count_2xx=0; count_4xx=0; count_5xx=0; count_502=0; count_total=0

_cleanup() {
  echo ""
  echo "${BLD}=== Summary ===${RST}"
  echo "  Total requests : ${count_total}"
  echo "  ${GRN}2xx${RST}             : ${count_2xx}"
  echo "  ${YLW}4xx${RST}             : ${count_4xx}"
  echo "  ${RED}5xx (503)${RST}       : ${count_5xx}"
  [ "${count_502}" -gt 0 ] && \
    echo "  ${RED}502 (no target)${RST} : ${count_502}"
  true
}
trap _cleanup EXIT

hit() {
  local method="$1" path="$2"
  local status colour
  status=$(curl -o /dev/null -sw '%{http_code}' -X "${method}" "${BASE_URL}${path}")
  count_total=$((count_total + 1))
  case "${status}" in
    2*)  count_2xx=$((count_2xx + 1));   colour="${GRN}" ;;
    404) count_4xx=$((count_4xx + 1));   colour="${YLW}" ;;
    502) count_502=$((count_502 + 1));   colour="${RED}" ;;
    5*)  count_5xx=$((count_5xx + 1));   colour="${RED}" ;;
    *)                                   colour="${YLW}" ;;
  esac
  printf "%s[%s]%s %-6s %-30s → %s%s%s\n" \
    "${BLD}" "$(date +%H:%M:%S)" "${RST}" "${method}" "${path}" "${colour}" "${status}" "${RST}"
}

traffic_loop() {
  local end_at=$(( $(date +%s) + $1 ))
  while [ "$(date +%s)" -lt "${end_at}" ]; do
    hit GET /api/items;      sleep 0.5
    hit GET /api/items/1;    sleep 0.5
    hit GET /api/items/99;   sleep 0.5
    hit GET /actuator/health; sleep 0.5
  done
}

_poll_recovery() {
  local recovery_time="" deadline consecutive_200s=0 status colour
  deadline=$(( toggle_time + POLL_TIMEOUT ))

  while [ "$(date +%s)" -lt "${deadline}" ]; do
    hit GET /api/items;    sleep 0.5
    hit GET /api/items/1;  sleep 0.5
    hit GET /api/items/99; sleep 0.5

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
        recovery_msg
        echo "${GRN}    Time from toggle to recovery: $(( recovery_time - toggle_time ))s${RST}"
        echo "${recovery_time}"
        return 0
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

  echo "${RED}${BLD}==> Timed out after ${POLL_TIMEOUT}s waiting for recovery${RST}"
  return 1
}

run_demo() {
  # URL discovery (cloud-specific)
  discover_url

  # Phase 1: baseline
  echo ""
  echo "${BLD}==> Phase 1: baseline traffic for ${SOAK}s — all requests should be 200/404${RST}"
  traffic_loop "${SOAK}"

  # Toggle DOWN
  toggle_time=$(date +%s)
  echo ""
  echo "${RED}${BLD}==> Toggling health → DOWN${RST}"
  toggle_hints
  curl -s -X POST "${BASE_URL}/health/toggle" | jq .
  echo ""

  # Phase 2: poll for platform-driven recovery
  echo "${BLD}==> Phase 2: waiting for platform to replace the instance (no manual toggle)${RST}"
  echo "${BLD}    503 = app reporting DOWN, 502 = no healthy target during handover${RST}"
  echo ""
  local recovered
  recovered=$(_poll_recovery) || exit 1

  # Phase 3: post-recovery soak
  echo ""
  echo "${BLD}==> Phase 3: post-recovery traffic for 30s — confirming stable 200s${RST}"
  traffic_loop 30

  # Fetch logs
  echo ""
  echo "${CYN}${BLD}==> Fetching logs around the replacement window${RST}"
  echo ""
  fetch_logs

  echo ""
  echo "${GRN}${BLD}==> Demo complete${RST}"
  echo "${GRN}    Look for the Spring Boot startup banner — that is the new instance.${RST}"
  echo "${GRN}    The timestamp gap around the toggle confirms the old instance was stopped.${RST}"
}
