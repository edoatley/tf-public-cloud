#!/usr/bin/env bash
# Demonstrates upload, update, download, and delete against a GCS bucket.
# Usage: ./scripts/examples/object-storage/gcp.sh
# The bucket name is looked up via the gcloud CLI.
set -euo pipefail

NAME_PREFIX="tf-public-cloud-object-storage"
KEY="demo/hello.txt"

echo "==> Looking up GCS bucket name"
BUCKET="$(gcloud storage buckets list --format='value(name)' \
  | grep "^${NAME_PREFIX}" | head -1)"
echo "     ${BUCKET}"
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
