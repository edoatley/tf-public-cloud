#!/usr/bin/env bash
# Demonstrates upload, update, download, and delete against an Azure Blob container.
# Usage: ./scripts/examples/object-storage-azure.sh
# The storage account name is looked up via the az CLI.
set -euo pipefail

NAME_PREFIX="tfpubcloudobjectstor"
CONTAINER="data"

echo "==> Looking up Azure storage account name"
ACCOUNT="$(az storage account list \
  --query "[?starts_with(name, '${NAME_PREFIX}')].name | [0]" \
  --output tsv)"
echo "     ${ACCOUNT}"
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

echo "==> Empty container (delete all remaining blobs including versions)"
az storage blob list \
  --account-name "$ACCOUNT" --container-name "$CONTAINER" \
  --include dv --auth-mode login \
  --query '[].name' -o tsv | sort -u | while read -r NAME; do
    az storage blob delete-batch \
      --account-name "$ACCOUNT" --source "$CONTAINER" \
      --pattern "${NAME}" --delete-snapshots include --auth-mode login
  done

echo "==> Done"
