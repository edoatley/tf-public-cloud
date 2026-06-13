#!/usr/bin/env bash
# One-time setup: generate an SSH key pair for VM deployments and store
# the public key as a base64-encoded GitHub Actions variable.
set -euo pipefail

KEY_FILE="$(mktemp -d)/vm_deploy_key"
REPO="${GITHUB_REPOSITORY:-}"

if [ -z "$REPO" ]; then
  # Try to detect from git remote
  REPO=$(git remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||;s|\.git$||' || true)
fi

if [ -z "$REPO" ]; then
  echo "ERROR: Cannot determine GitHub repository. Set GITHUB_REPOSITORY=owner/repo or run from inside the repo." >&2
  exit 1
fi

echo "Generating RSA 4096-bit SSH key pair..."
ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -N "" -C "vm-deploy-key" >/dev/null

echo "Base64-encoding public key..."
if [[ "$(uname)" == "Darwin" ]]; then
  B64=$(base64 -i "${KEY_FILE}.pub")
else
  B64=$(base64 -w0 "${KEY_FILE}.pub")
fi

echo "Setting SSH_PUBLIC_KEY variable on ${REPO}..."
gh variable set SSH_PUBLIC_KEY --body "$B64" --repo "$REPO"

echo ""
echo "Done. Your private key is at: ${KEY_FILE}"
echo ""
echo "Save it somewhere secure (e.g. 1Password, ~/.ssh/vm_deploy_key) then delete the temp file:"
echo "  cp ${KEY_FILE} ~/.ssh/vm_deploy_key && chmod 600 ~/.ssh/vm_deploy_key"
echo "  rm -f ${KEY_FILE} ${KEY_FILE}.pub"
echo ""
echo "To use locally with a VM module:"
echo "  terraform plan -var=\"ssh_public_key=\$(cat ~/.ssh/vm_deploy_key.pub)\""
