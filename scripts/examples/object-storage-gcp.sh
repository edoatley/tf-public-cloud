#!/usr/bin/env bash
# Demonstrates upload, update, download, and delete against a GCS bucket.
# Usage: ./scripts/object-storage-gcp.sh <bucket-name>
set -euo pipefail

BUCKET="${1:?Usage: $0 <bucket-name>}"
KEY="demo/hello.txt"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "==> Upload"
echo "hello from object-storage demo" > "$TMP/v1.txt"
gcloud storage cp "$TMP/v1.txt" "gs://${BUCKET}/${KEY}"

echo "==> Update (overwrite)"
echo "updated content" > "$TMP/v2.txt"
gcloud storage cp "$TMP/v2.txt" "gs://${BUCKET}/${KEY}"

echo "==> Read back"
gcloud storage cp "gs://${BUCKET}/${KEY}" "$TMP/downloaded.txt"
echo "Downloaded content: $(cat "$TMP/downloaded.txt")"

echo "==> Delete object"
gcloud storage rm "gs://${BUCKET}/${KEY}"

echo "==> Empty bucket (all objects and versions)"
gcloud storage rm --recursive --all-versions "gs://${BUCKET}/**" 2>/dev/null || true

echo "==> Done"
