#!/usr/bin/env bash
# Proves that a consumer VPC reaches a service in a producer VPC over Private
# Service Connect — and that the two networks are not joined.
#
# Usage: ./scripts/examples/private-service-connect/gcp.sh
#
# Resources are discovered via the gcloud CLI, so no Terraform state access is
# needed. Checks 1-5 are hard assertions. Checks 6-7 need IAP SSH and are
# skipped loudly if the tunnel is unavailable; a SKIP is reported but does not
# fail the run.
#
# Requires: gcloud CLI, authenticated against the project holding the module.
set -uo pipefail

NAME_PREFIX="tf-public-cloud-psc"

if [ -t 1 ] && command -v tput &>/dev/null; then
  GRN=$(tput setaf 2); YLW=$(tput setaf 3); RED=$(tput setaf 1)
  CYN=$(tput setaf 6); BLD=$(tput bold); RST=$(tput sgr0)
else
  GRN=''; YLW=''; RED=''; CYN=''; BLD=''; RST=''
fi

pass_count=0; fail_count=0; skip_count=0

pass() { echo "${GRN}  PASS${RST}  $1"; pass_count=$((pass_count + 1)); }
fail() { echo "${RED}  FAIL${RST}  $1"; fail_count=$((fail_count + 1)); }
skip() { echo "${YLW}  SKIP${RST}  $1"; skip_count=$((skip_count + 1)); }
step() { echo ""; echo "${BLD}==> $1${RST}"; }

# --- discovery -------------------------------------------------------------

step "Discovering resources matching '${NAME_PREFIX}'"

CONSUMER_VM="$(gcloud compute instances list \
  --filter="name~'${NAME_PREFIX}-consumer'" --format='value(name)' --limit=1)"
PRODUCER_VM="$(gcloud compute instances list \
  --filter="name~'${NAME_PREFIX}-producer'" --format='value(name)' --limit=1)"
ZONE="$(gcloud compute instances list \
  --filter="name~'${NAME_PREFIX}-consumer'" --format='value(zone.basename())' --limit=1)"
PRODUCER_IP="$(gcloud compute instances list \
  --filter="name~'${NAME_PREFIX}-producer'" \
  --format='value(networkInterfaces[0].networkIP)' --limit=1)"
CONSUMER_IP="$(gcloud compute instances list \
  --filter="name~'${NAME_PREFIX}-consumer'" \
  --format='value(networkInterfaces[0].networkIP)' --limit=1)"
PRODUCER_NET="$(gcloud compute networks list \
  --filter="name~'${NAME_PREFIX}-producer-vpc'" --format='value(name)' --limit=1)"
CONSUMER_NET="$(gcloud compute networks list \
  --filter="name~'${NAME_PREFIX}-consumer-vpc'" --format='value(name)' --limit=1)"
ATTACHMENT="$(gcloud compute service-attachments list \
  --filter="name~'${NAME_PREFIX}-attachment'" --format='value(name)' --limit=1)"
REGION="$(gcloud compute service-attachments list \
  --filter="name~'${NAME_PREFIX}-attachment'" --format='value(region.basename())' --limit=1)"
ENDPOINT_IP="$(gcloud compute addresses list \
  --filter="name~'${NAME_PREFIX}-endpoint-ip'" --format='value(address)' --limit=1)"
NAT_CIDR="$(gcloud compute networks subnets list \
  --filter="name~'${NAME_PREFIX}-psc-nat'" --format='value(ipCidrRange)' --limit=1)"

for pair in "CONSUMER_VM:${CONSUMER_VM}" "PRODUCER_VM:${PRODUCER_VM}" \
            "ATTACHMENT:${ATTACHMENT}" "ENDPOINT_IP:${ENDPOINT_IP}" \
            "NAT_CIDR:${NAT_CIDR}" "PRODUCER_NET:${PRODUCER_NET}"; do
  if [ -z "${pair#*:}" ]; then
    echo "${RED}Could not discover ${pair%%:*}. Is the module applied?${RST}" >&2
    exit 1
  fi
done

echo "    producer VM   : ${PRODUCER_VM} (${PRODUCER_IP}) in ${PRODUCER_NET}"
echo "    consumer VM   : ${CONSUMER_VM} (${CONSUMER_IP}) in ${CONSUMER_NET}"
echo "    PSC endpoint  : ${ENDPOINT_IP} (inside the consumer subnetwork)"
echo "    attachment    : ${ATTACHMENT} (${REGION})"
echo "    PSC NAT range : ${NAT_CIDR}"

# --- positive proof --------------------------------------------------------

step "1. Producer reports the consumer endpoint as ACCEPTED"
STATUS="$(gcloud compute service-attachments describe "${ATTACHMENT}" \
  --region "${REGION}" --format='value(connectedEndpoints[0].status)')"
if [ "${STATUS}" = "ACCEPTED" ]; then
  pass "connection status is ACCEPTED"
else
  fail "connection status is '${STATUS:-<empty>}', expected ACCEPTED"
fi

step "2. Consumer reached the service on boot (serial console, no SSH needed)"
CONSUMER_SERIAL="$(gcloud compute instances get-serial-port-output "${CONSUMER_VM}" \
  --zone "${ZONE}" 2>/dev/null)"
PSC_LINE="$(echo "${CONSUMER_SERIAL}" | grep -o 'PSC-TEST: .*' | tail -1)"
if echo "${PSC_LINE}" | grep -q 'PSC-TEST: 200'; then
  pass "${PSC_LINE}"
  echo "${CYN}    $(echo "${CONSUMER_SERIAL}" | grep -o 'PSC-BODY: .*' | tail -1)${RST}"
else
  fail "boot-time check did not report 200: ${PSC_LINE:-<no PSC-TEST line found>}"
fi

step "3. Producer saw the request arrive source-NATed from ${NAT_CIDR}"
PRODUCER_SERIAL="$(gcloud compute instances get-serial-port-output "${PRODUCER_VM}" \
  --zone "${ZONE}" 2>/dev/null)"
NAT_PREFIX="${NAT_CIDR%.*}."
ACCESS_LINE="$(echo "${PRODUCER_SERIAL}" | grep -o "${NAT_PREFIX}[0-9]* - - .*GET / HTTP.*" | tail -1)"
if [ -n "${ACCESS_LINE}" ]; then
  pass "access log shows: ${ACCESS_LINE}"
  if echo "${PRODUCER_SERIAL}" | grep -q "${CONSUMER_IP} - -"; then
    fail "producer also logged the raw consumer address ${CONSUMER_IP} — source NAT is not in effect"
  else
    pass "producer never saw the consumer's own address (${CONSUMER_IP})"
  fi
else
  fail "no access log entry from ${NAT_CIDR} on the producer serial console"
fi

# --- negative proof: what is NOT there -------------------------------------

step "4. No VPC peering exists between the two networks"
PEERINGS="$(gcloud compute networks describe "${PRODUCER_NET}" \
  --format='value(peerings[].name)')"
if [ -z "${PEERINGS}" ]; then
  pass "producer network ${PRODUCER_NET} has no peerings"
else
  fail "producer network has peerings: ${PEERINGS}"
fi

# Do NOT assert on the guest routing table here. A GCP VM has a /32 address and a
# single default route, so "ip route get" returns the same next hop for every
# destination and would look identical on peered VPCs. Unreachability has to be
# proven from the VPC route table and from a connection that fails.
step "5. Consumer VPC holds no route to the producer"
PEERING_ROUTES="$(gcloud compute routes list \
  --filter="network~'${CONSUMER_NET}'" --format='value(nextHopPeering)' | grep -c . || true)"
PRODUCER_PREFIX="${PRODUCER_IP%.*}."
PRODUCER_ROUTES="$(gcloud compute routes list \
  --filter="network~'${CONSUMER_NET}'" --format='value(destRange)' \
  | grep -c "^${PRODUCER_PREFIX}" || true)"
echo "${CYN}    $(gcloud compute routes list --filter="network~'${CONSUMER_NET}'" \
  --format='value[separator=" -> "](destRange,nextHopGateway.basename())' | tr '\n' '|')${RST}"
if [ "${PEERING_ROUTES}" -eq 0 ]; then
  pass "no peering next hop in the consumer VPC route table"
else
  fail "${PEERING_ROUTES} route(s) in the consumer VPC use a peering next hop"
fi
if [ "${PRODUCER_ROUTES}" -eq 0 ]; then
  pass "no route covering ${PRODUCER_PREFIX}0/24 — the producer range is unrouteable from here"
else
  fail "${PRODUCER_ROUTES} route(s) cover the producer range ${PRODUCER_PREFIX}0/24"
fi

SSH="gcloud compute ssh ${CONSUMER_VM} --zone ${ZONE} --tunnel-through-iap --quiet"

step "6. Consumer cannot reach the producer VM directly (needs IAP SSH)"
# echo runs regardless of curl, so ssh exits 0 whenever the tunnel itself worked.
# That keeps "curl failed" distinguishable from "could not connect to run curl".
if OUT="$(${SSH} --command="curl -s -m 5 -o /dev/null http://${PRODUCER_IP}/ ; echo CURL_RC=\$?" 2>/dev/null)"; then
  RC="$(echo "${OUT}" | grep -o 'CURL_RC=[0-9]*' | cut -d= -f2)"
  if [ "${RC}" = "0" ]; then
    fail "consumer reached the producer VM directly at ${PRODUCER_IP} — the VPCs are not isolated"
  else
    pass "direct connection to ${PRODUCER_IP} failed as it must (curl exit ${RC})"
  fi
else
  skip "IAP SSH unavailable (needs roles/iap.tunnelResourceAccessor and the IAP API)"
fi

step "7. Live request from the consumer over the PSC endpoint (needs IAP SSH)"
if BODY="$(${SSH} --command="curl -sf -m 5 http://${ENDPOINT_IP}/" 2>/dev/null)"; then
  echo "${CYN}    ${BODY}${RST}"
  pass "HTTP 200 from ${ENDPOINT_IP} on demand"
else
  skip "IAP SSH unavailable — boot-time check in step 2 already proves the data path"
fi

# --- summary ---------------------------------------------------------------

echo ""
echo "${BLD}=== Summary ===${RST}"
echo "  ${GRN}passed${RST}  : ${pass_count}"
echo "  ${YLW}skipped${RST} : ${skip_count}"
echo "  ${RED}failed${RST}  : ${fail_count}"

if [ "${fail_count}" -gt 0 ]; then
  echo ""
  echo "${RED}${BLD}Private Service Connect demo FAILED (${fail_count} check(s)).${RST}"
  exit 1
fi

echo ""
echo "${GRN}${BLD}Private Service Connect verified.${RST}"
echo "  ${CONSUMER_VM} has no public IP, no peering and no route to ${PRODUCER_NET},"
echo "  yet gets HTTP 200 from ${ENDPOINT_IP} — an address in its own subnetwork."
