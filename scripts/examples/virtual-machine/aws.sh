#!/usr/bin/env bash
# Proves SSH connectivity to an AWS EC2 instance by listing the root directory.
# Usage: ./scripts/examples/virtual-machine/aws.sh [private-key-path]
# The instance public IP is looked up via the AWS CLI.
# AWS_PROFILE defaults to 'sandbox'.
set -euo pipefail
export AWS_PAGER=""
export AWS_PROFILE="${AWS_PROFILE:-sandbox}"

KEY="${1:-${VM_KEY:-$HOME/.ssh/vm_deploy_key}}"
USER="ec2-user"
NAME_PREFIX="tf-public-cloud"

echo "==> Looking up EC2 instance public IP"
HOST="$(aws ec2 describe-instances \
  --region eu-west-2 \
  --filters "Name=instance-state-name,Values=running" \
            "Name=key-name,Values=*${NAME_PREFIX}*" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)"
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
