#!/usr/bin/env bash
# Demonstrates upload, update, download, and delete against an S3 bucket.
# Usage: ./scripts/examples/object-storage-aws.sh
# The bucket name is looked up via the AWS CLI.
# AWS_PROFILE defaults to 'sandbox'.
set -euo pipefail
export AWS_PAGER=""
export AWS_PROFILE="${AWS_PROFILE:-sandbox}"

NAME_PREFIX="tf-public-cloud-object-storage"
KEY="demo/hello.txt"

echo "==> Looking up S3 bucket name"
BUCKET="$(aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, '${NAME_PREFIX}')].Name | [0]" \
  --output text)"
echo "     ${BUCKET}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "==> Upload"
echo "hello from object-storage demo" > "$TMP/v1.txt"
aws s3 cp "$TMP/v1.txt" "s3://${BUCKET}/${KEY}"

echo "==> Update (overwrite)"
echo "updated content" > "$TMP/v2.txt"
aws s3 cp "$TMP/v2.txt" "s3://${BUCKET}/${KEY}"

echo "==> Read back"
aws s3 cp "s3://${BUCKET}/${KEY}" "$TMP/downloaded.txt"
echo "Downloaded content: $(cat "$TMP/downloaded.txt")"

echo "==> Delete object"
aws s3 rm "s3://${BUCKET}/${KEY}"

echo "==> Empty bucket (all versions and delete markers)"
VERSIONS=$(aws s3api list-object-versions --bucket "${BUCKET}" \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
  --output json)
if [ "$(echo "${VERSIONS}" | jq '.Objects')" != "null" ]; then
  echo "${VERSIONS}" | aws s3api delete-objects --bucket "${BUCKET}" --delete file:///dev/stdin
fi
DELETE_MARKERS=$(aws s3api list-object-versions --bucket "${BUCKET}" \
  --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
  --output json)
if [ "$(echo "${DELETE_MARKERS}" | jq '.Objects')" != "null" ]; then
  echo "${DELETE_MARKERS}" | aws s3api delete-objects --bucket "${BUCKET}" --delete file:///dev/stdin
fi

echo "==> Done"
