#!/usr/bin/env bash
# Applies or removes GCP IAM bindings defined in a JSON file.
# Safe to re-run — add/remove-iam-policy-binding are idempotent.
#
# Usage:
#   ./scripts/apply-gcp-iam-bindings.sh [--remove] <service-account-email> <json-bindings-file>
#
# Examples:
#   # Add all bindings in the file
#   ./scripts/apply-gcp-iam-bindings.sh \
#     github-actions-tf@gcp-sandbox-2026-18798.iam.gserviceaccount.com \
#     scripts/iam/gcp-permissions.json
#
#   # Remove all bindings in the file
#   ./scripts/apply-gcp-iam-bindings.sh --remove \
#     github-actions-tf@gcp-sandbox-2026-18798.iam.gserviceaccount.com \
#     scripts/iam/gcp-permissions.json
#
# JSON format — array of objects with fields:
#   role:     GCP IAM role (e.g. roles/storage.objectAdmin)
#   scope:    "bucket" or "project"
#   resource: bucket name or project ID (depending on scope)
#   comment:  (optional) ignored, for documentation only

set -euo pipefail

# Parse optional --remove flag
MODE="apply"
if [[ "${1:-}" == "--remove" ]]; then
  MODE="remove"
  shift
fi

GSA_EMAIL="${1:?Usage: $0 [--remove] <service-account-email> <json-bindings-file>}"
BINDINGS_FILE="${2:?Usage: $0 [--remove] <service-account-email> <json-bindings-file>}"

if [ ! -f "${BINDINGS_FILE}" ]; then
  echo "Error: bindings file '${BINDINGS_FILE}' not found." >&2
  exit 1
fi

ACTION_LABEL=$([ "${MODE}" = "remove" ] && echo "Removing" || echo "Applying")
echo "==> ${ACTION_LABEL} GCP IAM bindings"
echo "    Member:        serviceAccount:${GSA_EMAIL}"
echo "    Bindings file: ${BINDINGS_FILE}"
echo "    Mode:          ${MODE}"
echo ""

MEMBER="serviceAccount:${GSA_EMAIL}"
COUNT=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))))" "${BINDINGS_FILE}")
echo "    ${COUNT} binding(s) to ${MODE}"
echo ""

python3 - "${BINDINGS_FILE}" "${MEMBER}" "${MODE}" <<'EOF'
import json, subprocess, sys

bindings_file = sys.argv[1]
member        = sys.argv[2]
mode          = sys.argv[3]

with open(bindings_file) as f:
    bindings = json.load(f)

for b in bindings:
    role     = b["role"]
    scope    = b["scope"]
    resource = b["resource"]
    comment  = b.get("comment", "")

    label = "REMOVE" if mode == "remove" else "APPLY"
    print(f"[{label}] {role}")
    print(f"         scope={scope} resource={resource}")
    if comment:
        print(f"         # {comment}")

    if scope == "bucket":
        sub = ["storage", "buckets",
               "remove-iam-policy-binding" if mode == "remove" else "add-iam-policy-binding",
               f"gs://{resource}",
               f"--member={member}",
               f"--role={role}"]
    elif scope == "project":
        sub = ["projects",
               "remove-iam-policy-binding" if mode == "remove" else "add-iam-policy-binding",
               resource,
               f"--member={member}",
               f"--role={role}"]
    else:
        print(f"Error: unknown scope '{scope}' — must be 'bucket' or 'project'", file=sys.stderr)
        sys.exit(1)

    cmd = ["gcloud"] + sub
    result = subprocess.run(cmd, capture_output=True, text=True)

    # Removing a binding that doesn't exist is not an error
    if result.returncode != 0:
        if mode == "remove" and "not found" in result.stderr.lower():
            print("         [SKIP] binding not present")
        else:
            print(f"Error: {result.stderr}", file=sys.stderr)
            sys.exit(1)
    else:
        print("         [OK]")
    print()

print(f"==> All bindings {'removed' if mode == 'remove' else 'applied'}.")
EOF

echo ""
echo "==> Done. Current bindings for this member:"
gcloud projects get-iam-policy "$(python3 -c "
import json
bindings = json.load(open('${BINDINGS_FILE}'))
projects = [b['resource'] for b in bindings if b['scope'] == 'project']
print(projects[0] if projects else '')
")" \
  --flatten='bindings[].members' \
  --filter="bindings.members:${GSA_EMAIL}" \
  --format='table(bindings.role)' 2>/dev/null || true
