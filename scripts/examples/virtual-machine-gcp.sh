#!/usr/bin/env bash
# Proves SSH connectivity to a GCP Compute Engine instance by listing the root directory.
# Usage: ./scripts/examples/virtual-machine-gcp.sh <public-ip> <private-key-path>
set -euo pipefail

HOST="${1:?Usage: $0 <public-ip> <private-key-path>}"
KEY="${2:?Usage: $0 <public-ip> <private-key-path>}"
USER="debian"

SSH="ssh -i ${KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${USER}@${HOST}"

echo "==> Connecting to ${USER}@${HOST}"

echo "==> Root directory listing"
$SSH "ls -la /"

echo "==> Hostname"
$SSH "hostname"

echo "==> OS release"
$SSH "cat /etc/os-release | grep PRETTY_NAME"

echo "==> Done"
