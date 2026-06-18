#!/usr/bin/env bash
# Proves SSH connectivity to an Azure Linux VM by listing the root directory.
# Usage: ./scripts/examples/virtual-machine-azure.sh [private-key-path]
# The VM public IP is looked up via the az CLI.
set -euo pipefail

KEY="${1:-${VM_KEY:-$HOME/.ssh/vm_deploy_key}}"
USER="azureuser"
NAME_PREFIX="tfpubcloudvm"

echo "==> Looking up Azure VM public IP"
HOST="$(az vm list-ip-addresses \
  --query "[?contains(virtualMachine.name, '${NAME_PREFIX}')].virtualMachine.network.publicIpAddresses[0].ipAddress | [0]" \
  --output tsv)"
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
