#!/usr/bin/env bash
# Run trivy misconfiguration scan against one module or all modules.
# Usage:
#   ./scripts/tools/trivy.sh                    # scan all modules
#   ./scripts/tools/trivy.sh aws/object-storage  # scan one module
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

if ! command -v trivy > /dev/null 2>&1; then
  echo "trivy not found. Install: brew install trivy"
  exit 1
fi

if [[ $# -gt 0 ]]; then
  modules=("$REPO_ROOT/$1")
else
  mapfile -t modules < <(find "$REPO_ROOT" -name "terraform.tf" -not -path "*/.terraform/*" | xargs -I{} dirname {} | sort)
fi

overall=0

for module in "${modules[@]}"; do
  rel="${module#"$REPO_ROOT/"}"
  echo ""
  echo "=== trivy: $rel ==="
  if ! trivy fs --scanners misconfig --no-progress "$module"; then
    overall=1
  fi
done

echo ""
if [[ $overall -ne 0 ]]; then
  echo "trivy found issues."
  exit 1
fi
echo "trivy: no issues found."
exit 0
