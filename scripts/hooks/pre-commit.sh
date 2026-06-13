#!/usr/bin/env bash
# Pre-commit hook: runs fmt-check, validate, and tflint on staged Terraform modules.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

# Collect unique module directories that have staged .tf changes
declare -A seen
staged_modules=()
while IFS= read -r file; do
  dir="$(dirname "$REPO_ROOT/$file")"
  if [[ -f "$dir/terraform.tf" ]] && [[ -z "${seen[$dir]+x}" ]]; then
    seen["$dir"]=1
    staged_modules+=("$dir")
  fi
done < <(git diff --cached --name-only --diff-filter=ACMR | grep '\.tf$' || true)

if [[ ${#staged_modules[@]} -eq 0 ]]; then
  echo "[pre-commit] No staged Terraform changes — skipping."
  exit 0
fi

errors=0

for module in "${staged_modules[@]}"; do
  rel="${module#"$REPO_ROOT/"}"
  echo ""
  echo "[pre-commit] Checking: $rel"

  # fmt check
  echo "  → terraform fmt -check"
  if ! terraform fmt -check "$module" > /dev/null 2>&1; then
    echo "  FAIL: formatting issues (run: terraform fmt $rel)"
    errors=$((errors + 1))
  fi

  # validate (requires init; skip gracefully if not initialised)
  if [[ -d "$module/.terraform" ]]; then
    echo "  → terraform validate"
    if ! terraform -chdir="$module" validate -no-color > /tmp/tf-validate-out.txt 2>&1; then
      echo "  FAIL: validation errors"
      sed 's/^/    /' /tmp/tf-validate-out.txt
      errors=$((errors + 1))
    fi
  else
    echo "  SKIP: terraform validate ($rel not initialised — run terraform init first)"
  fi

  # tflint
  if command -v tflint > /dev/null 2>&1; then
    echo "  → tflint"
    if ! tflint --chdir="$module" --no-color > /tmp/tflint-out.txt 2>&1; then
      echo "  FAIL: tflint findings"
      sed 's/^/    /' /tmp/tflint-out.txt
      errors=$((errors + 1))
    fi
  else
    echo "  SKIP: tflint not found"
  fi
done

echo ""
if [[ $errors -gt 0 ]]; then
  echo "[pre-commit] $errors check(s) failed. Commit blocked."
  exit 1
fi

echo "[pre-commit] All checks passed."
exit 0
