#!/usr/bin/env bash
# One-time setup: generate an SSH key pair for VM deployments and store
# the public key as a base64-encoded GitHub Actions variable.
set -euo pipefail

KEY_FILE="${HOME}/.ssh/vm_deploy_key"
REPO="${GITHUB_REPOSITORY:-}"

if [ -z "$REPO" ]; then
  # Try to detect from git remote
  REPO=$(git remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||;s|\.git$||' || true)
fi

if [ -z "$REPO" ]; then
  echo "ERROR: Cannot determine GitHub repository. Set GITHUB_REPOSITORY=owner/repo or run from inside the repo." >&2
  exit 1
fi

mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"

if [ -f "$KEY_FILE" ]; then
  echo "WARNING: ${KEY_FILE} already exists. Overwrite? [y/N] "
  read -r CONFIRM
  if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

echo "Generating RSA 4096-bit SSH key pair..."
ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -N "" -C "vm-deploy-key" >/dev/null
chmod 600 "$KEY_FILE"

echo "Base64-encoding public key..."
if [[ "$(uname)" == "Darwin" ]]; then
  B64=$(base64 -i "${KEY_FILE}.pub")
else
  B64=$(base64 -w0 "${KEY_FILE}.pub")
fi

echo "Setting SSH_PUBLIC_KEY variable on ${REPO}..."
gh variable set SSH_PUBLIC_KEY --body "$B64" --repo "$REPO"

echo ""
echo "Done."
echo "  Private key: ${KEY_FILE}"
echo "  Public key:  ${KEY_FILE}.pub"
echo ""
echo "To use locally with a VM module:"
echo "  terraform plan -var=\"ssh_public_key=\$(cat ${KEY_FILE}.pub)\""
