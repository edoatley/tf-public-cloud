#!/usr/bin/env bash
# Proves SSH connectivity to a GCP Compute Engine instance by listing the root directory.
# Usage: ./scripts/examples/virtual-machine-gcp.sh [private-key-path]
# The instance public IP is looked up via the gcloud CLI.
set -euo pipefail

KEY="${1:-${VM_KEY:-$HOME/.ssh/vm_deploy_key}}"
USER="debian"
NAME_PREFIX="tf-public-cloud"

echo "==> Looking up Compute Engine instance public IP"
HOST="$(gcloud compute instances list \
  --filter="name~'${NAME_PREFIX}' AND status=RUNNING" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)' \
  --limit=1)"
echo "     ${HOST}"

SSH="ssh -i ${KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${USER}@${HOST}"

echo "==> Connecting to ${USER}@${HOST}"

echo "==> Root directory listing"
$SSH "ls -la /"

echo "==> Hostname"
$SSH "hostname"

echo "==> OS release"
$SSH "cat /etc/os-release | grep PRETTY_NAME"

echo "==> Done"
