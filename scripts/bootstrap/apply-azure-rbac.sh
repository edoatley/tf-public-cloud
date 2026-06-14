#!/usr/bin/env bash
# Applies or removes Azure RBAC role assignments defined in a JSON file.
# Safe to re-run — role assignments are idempotent.
#
# Usage:
#   ./scripts/apply-azure-rbac.sh [--remove] <service-principal-client-id> <json-permissions-file>
#
# Examples:
#   # Add all role assignments in the file
#   ./scripts/apply-azure-rbac.sh YOUR_CLIENT_ID scripts/iam/azure-permissions.json
#
#   # Remove all role assignments in the file
#   ./scripts/apply-azure-rbac.sh --remove YOUR_CLIENT_ID scripts/iam/azure-permissions.json
#
# JSON format — array of objects with fields:
#   role:           Azure built-in role name (e.g. "Storage Blob Data Contributor")
#   scope:          "subscription", "resource_group", or "storage_account"
#   resource:       resource group name or storage account name (depending on scope)
#   resource_group: required when scope is "storage_account"
#   comment:        (optional) ignored, for documentation only

set -euo pipefail

AZ_SUBSCRIPTION=edbc314c-06b5-431f-bcc9-40267e377669

# Parse optional --remove flag
MODE="apply"
if [[ "${1:-}" == "--remove" ]]; then
  MODE="remove"
  shift
fi

SP_CLIENT_ID="${1:?Usage: $0 [--remove] <service-principal-client-id> <json-permissions-file>}"
PERMISSIONS_FILE="${2:?Usage: $0 [--remove] <service-principal-client-id> <json-permissions-file>}"

if [ ! -f "${PERMISSIONS_FILE}" ]; then
  echo "Error: permissions file '${PERMISSIONS_FILE}' not found." >&2
  exit 1
fi

ACTION_LABEL=$([ "${MODE}" = "remove" ] && echo "Removing" || echo "Applying")
echo "==> ${ACTION_LABEL} Azure RBAC assignments"
echo "    Service principal: ${SP_CLIENT_ID}"
echo "    Permissions file:  ${PERMISSIONS_FILE}"
echo "    Subscription:      ${AZ_SUBSCRIPTION}"
echo "    Mode:              ${MODE}"
echo ""

az account set --subscription "${AZ_SUBSCRIPTION}"

COUNT=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))))" "${PERMISSIONS_FILE}")
echo "    ${COUNT} assignment(s) to ${MODE}"
echo ""

python3 - "${PERMISSIONS_FILE}" "${SP_CLIENT_ID}" "${AZ_SUBSCRIPTION}" "${MODE}" <<'EOF'
import json, subprocess, sys

permissions_file = sys.argv[1]
sp_client_id     = sys.argv[2]
subscription     = sys.argv[3]
mode             = sys.argv[4]

with open(permissions_file) as f:
    assignments = json.load(f)

def build_scope(a, subscription):
    s = a["scope"]
    r = a["resource"]
    if s == "subscription":
        return f"/subscriptions/{subscription}"
    elif s == "resource_group":
        return f"/subscriptions/{subscription}/resourceGroups/{r}"
    elif s == "storage_account":
        rg = a.get("resource_group")
        if not rg:
            print(f"Error: 'resource_group' required when scope is 'storage_account'", file=sys.stderr)
            sys.exit(1)
        return f"/subscriptions/{subscription}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{r}"
    else:
        print(f"Error: unknown scope '{s}' — must be subscription, resource_group, or storage_account", file=sys.stderr)
        sys.exit(1)

for a in assignments:
    role    = a["role"]
    comment = a.get("comment", "")
    scope   = build_scope(a, subscription)

    label = "REMOVE" if mode == "remove" else "APPLY"
    print(f"[{label}] {role}")
    print(f"         scope={a['scope']} resource={a['resource']}")
    if comment:
        print(f"         # {comment}")

    if mode == "remove":
        cmd = [
            "az", "role", "assignment", "delete",
            "--assignee", sp_client_id,
            "--role", role,
            "--scope", scope,
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            if "does not exist" in result.stderr.lower() or "no matches" in result.stderr.lower():
                print("         [SKIP] assignment not present")
            else:
                print(f"Error: {result.stderr}", file=sys.stderr)
                sys.exit(1)
        else:
            print("         [OK]")
    else:
        # Check if assignment already exists to give a cleaner SKIP message
        check = subprocess.run([
            "az", "role", "assignment", "list",
            "--assignee", sp_client_id,
            "--role", role,
            "--scope", scope,
            "--query", "length(@)",
            "--output", "tsv",
        ], capture_output=True, text=True)
        if check.returncode == 0 and check.stdout.strip() != "0":
            print("         [SKIP] assignment already exists")
        else:
            cmd = [
                "az", "role", "assignment", "create",
                "--assignee", sp_client_id,
                "--role", role,
                "--scope", scope,
                "--output", "none",
            ]
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                print(f"Error: {result.stderr}", file=sys.stderr)
                sys.exit(1)
            print("         [OK]")
    print()

print(f"==> All assignments {'removed' if mode == 'remove' else 'applied'}.")
EOF

echo ""
echo "==> Done. Current role assignments for this principal:"
az role assignment list \
  --assignee "${SP_CLIENT_ID}" \
  --query '[].{Role:roleDefinitionName, Scope:scope}' \
  --output table 2>/dev/null || true
