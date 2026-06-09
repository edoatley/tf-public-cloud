#!/usr/bin/env bash
# Demonstrates upload, update, download, and delete against an Azure Blob container.
# Usage: ./scripts/object-storage-azure.sh <storage-account-name> [container-name]
set -euo pipefail

ACCOUNT="${1:?Usage: $0 <storage-account-name> [container-name]}"
CONTAINER="${2:-data}"
BLOB="demo/hello.txt"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "==> Upload"
echo "hello from object-storage demo" > "$TMP/v1.txt"
az storage blob upload \
  --account-name "$ACCOUNT" --container-name "$CONTAINER" \
  --name "$BLOB" --file "$TMP/v1.txt" --auth-mode login --overwrite

echo "==> Update (overwrite)"
echo "updated content" > "$TMP/v2.txt"
az storage blob upload \
  --account-name "$ACCOUNT" --container-name "$CONTAINER" \
  --name "$BLOB" --file "$TMP/v2.txt" --auth-mode login --overwrite

echo "==> Read back"
az storage blob download \
  --account-name "$ACCOUNT" --container-name "$CONTAINER" \
  --name "$BLOB" --file "$TMP/downloaded.txt" --auth-mode login
echo "Downloaded content: $(cat "$TMP/downloaded.txt")"

echo "==> Delete object"
az storage blob delete \
  --account-name "$ACCOUNT" --container-name "$CONTAINER" \
  --name "$BLOB" --auth-mode login

echo "==> Empty container (all blobs and versions)"
az storage blob list \
  --account-name "$ACCOUNT" --container-name "$CONTAINER" \
  --include dv --auth-mode login \
  --query '[].{name:name,versionId:versionId}' -o json | \
  jq -c '.[]' | while read -r ITEM; do
    NAME=$(echo "${ITEM}" | jq -r '.name')
    VERSION=$(echo "${ITEM}" | jq -r '.versionId')
    az storage blob delete \
      --account-name "$ACCOUNT" --container-name "$CONTAINER" \
      --name "${NAME}" --version-id "${VERSION}" --auth-mode login
  done

echo "==> Done"
