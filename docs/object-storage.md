# Object Storage

Comparison of the object-storage example across all three clouds.

## What each example provisions

|                             | AWS                                    | GCP                                   | Azure                                                |
| --------------------------- | -------------------------------------- | ------------------------------------- | ---------------------------------------------------- |
| **Module path**             | `aws/object-storage`                   | `gcp/object-storage`                  | `azure/object-storage`                               |
| **Primary resource**        | S3 bucket                              | GCS bucket                            | Storage Account + Blob Container                     |
| **Versioning**              | Enabled                                | Enabled                               | Enabled                                              |
| **Encryption**              | SSE-S3 (default) or SSE-KMS            | Google-managed (default) or CMEK      | Microsoft-managed (default)                          |
| **Public access**           | Blocked at account level               | `public_access_prevention = enforced` | `allow_nested_items_to_be_public = false`            |
| **HTTPS enforcement**       | Bucket policy denying non-TLS requests | Inherent (GCS is HTTPS-only)          | `https_traffic_only_enabled = true`, TLS 1.2 minimum |
| **Soft delete / retention** | —                                      | —                                     | 7-day blob + container delete retention              |
| **Tagging / labelling**     | `default_tags` on provider             | `labels` on resource                  | `tags` on resource group + account                   |

## AWS

S3 bucket with versioning, server-side encryption, and a bucket policy that denies any non-HTTPS request.

**Required variables:**

- `bucket_name` — globally unique S3 bucket name

**Optional variables (all have defaults):**

- `region` — defaults to `eu-west-2`
- `enable_kms` — set `true` to use SSE-KMS instead of SSE-S3
- `kms_key_arn` — required when `enable_kms = true`
- `tags` — passed to the provider `default_tags` block

**Key design decisions:**

- Public access block is applied before the bucket policy (`depends_on`) to avoid a race condition
- `bucket_key_enabled` is set when using KMS to reduce API call costs
- HTTPS enforcement is a deny statement on `aws:SecureTransport = false`, not a managed policy

## GCP

GCS bucket with uniform bucket-level access, public access prevention enforced, versioning, and optional CMEK.

**Required variables:**

- `project` — GCP project ID
- `bucket_name` — globally unique GCS bucket name

**Optional variables (all have defaults):**

- `region` — defaults to `europe-west2`
- `kms_key_name` — Cloud KMS key resource name; omit for Google-managed encryption
- `labels` — key/value labels applied to the bucket

**Key design decisions:**

- `uniform_bucket_level_access = true` disables per-object ACLs in favour of IAM
- `public_access_prevention = "enforced"` prevents any public grant even if uniform access is later changed
- `force_destroy = false` protects against accidental deletion of non-empty buckets
- CMEK is applied via a `dynamic` block — no encryption block is emitted when `kms_key_name` is null

## Azure

Storage Account with a private Blob Container. The example also creates the resource group that owns both resources.

**Required variables:**

- `subscription_id` — Azure subscription ID (injected via `TF_VAR_subscription_id` in CI)
- `resource_group_name` — name of the resource group to create
- `storage_account_name` — 3–24 lowercase alphanumeric, globally unique

**Optional variables (all have defaults):**

- `location` — defaults to `uksouth`
- `container_name` — defaults to `data`
- `account_replication_type` — defaults to `LRS`; use `GRS`, `ZRS`, or `GZRS` for higher durability
- `tags` — applied to both the resource group and storage account

**Key design decisions:**

- `skip_provider_registration = true` on the provider avoids needing subscription-level write access in CI
- `use_oidc = true` aligns with the OIDC-based GitHub Actions authentication
- Soft-delete retention (7 days) is set for both blobs and containers as a safety net
- The container uses `container_access_type = "private"` — no anonymous access

## Deploying

```sh
cd <cloud>/object-storage

# AWS
terraform init
terraform apply -var="bucket_name=my-unique-bucket"

# GCP
terraform init
terraform apply -var="project=my-gcp-project" -var="bucket_name=my-unique-bucket"

# Azure (subscription_id can also be set via TF_VAR_subscription_id env var)
terraform init
terraform apply \
  -var="subscription_id=<your-subscription-id>" \
  -var="resource_group_name=rg-my-example" \
  -var="storage_account_name=mystorageacct"
```

For repeated local use, create a gitignored `terraform.tfvars` in the module directory rather than passing `-var` flags each time.

## Working with objects

After deploying, use the helper scripts in `scripts/` to upload, update, read back, and delete a file. Each script takes the resource name(s) from `terraform output`.

### AWS (objects)

```sh
BUCKET=$(terraform -chdir=aws/object-storage output -raw bucket_name)
./scripts/object-storage-aws.sh "$BUCKET"
```

<details>
<summary>Example AWS Output</summary>

```terminaloutput
==> Upload
upload: ../../../../var/folders/_n/60jwg_ln5k78bwvr4p4x1sn40000gn/T/tmp.qp4dce8wLx/v1.txt to s3://tf-public-cloud-object-storage-32f9/demo/hello.txt
==> Update (overwrite)
upload: ../../../../var/folders/_n/60jwg_ln5k78bwvr4p4x1sn40000gn/T/tmp.qp4dce8wLx/v2.txt to s3://tf-public-cloud-object-storage-32f9/demo/hello.txt
==> Read back
download: s3://tf-public-cloud-object-storage-32f9/demo/hello.txt to ../../../../var/folders/_n/60jwg_ln5k78bwvr4p4x1sn40000gn/T/tmp.qp4dce8wLx/downloaded.txt
Downloaded content: updated content
==> Delete object
delete: s3://tf-public-cloud-object-storage-32f9/demo/hello.txt
==> Empty bucket (all versions and delete markers)
==> Done
```

</details>

### GCP (objects)

```sh
BUCKET=$(terraform -chdir=gcp/object-storage output -raw bucket_name)
./scripts/object-storage-gcp.sh "$BUCKET"
```

<details>
<summary>Example GCP Output</summary>

```terminaloutput
==> Upload
Copying file:///var/folders/_n/60jwg_ln5k78bwvr4p4x1sn40000gn/T/tmp.nGEyaBb0g9/v1.txt to gs://tf-public-cloud-object-storage-a003/demo/hello.txt
  Completed files 1/1 | 31.0B/31.0B                                            
==> Update (overwrite)
Copying file:///var/folders/_n/60jwg_ln5k78bwvr4p4x1sn40000gn/T/tmp.nGEyaBb0g9/v2.txt to gs://tf-public-cloud-object-storage-a003/demo/hello.txt
  Completed files 1/1 | 16.0B/16.0B                                            
==> Read back
Copying gs://tf-public-cloud-object-storage-a003/demo/hello.txt to file:///var/folders/_n/60jwg_ln5k78bwvr4p4x1sn40000gn/T/tmp.nGEyaBb0g9/downloaded.txt
  Completed files 1/1 | 16.0B/16.0B                                            
Downloaded content: updated content
==> Delete object
Removing objects:
⠏Removing gs://tf-public-cloud-object-storage-a003/demo/hello.txt...           
  Completed 1/1                                                                
==> Empty bucket (all objects and versions)
==> Done
```

</details>

### Azure (objects)

```sh
ACCOUNT=$(terraform -chdir=azure/object-storage output -raw storage_account_name)
CONTAINER=$(terraform -chdir=azure/object-storage output -raw container_name)
./scripts/object-storage-azure.sh "$ACCOUNT" "$CONTAINER"
```

. [!Note]
> For Azure the local user running the script needs additional permissions on the data plane.
> This can be granted with the cli like this:
>
> ```
> az role assignment create \
>    --role "Storage Blob Data Contributor" \
>    --assignee $(az ad signed-in-user show --query id -o tsv) \
>    --scope $(az storage account show --name my-sa --resource-group my-rg --query id -o tsv)
> ```


<details>
<summary>Example GCP Output</summary>

```terminaloutput
==> Upload
Finished[#############################################################]  100.0000%
{
  "client_request_id": "eb3966b4-66fc-11f1-bc95-acde48001122",
  "content_md5": "euXnruR3f3GUAHHFUoC5fw==",
  "date": "2026-06-13T07:53:09+00:00",
  "encryption_key_sha256": null,
  "encryption_scope": null,
  "etag": "\"0x8DEC920CFBA5510\"",
  "lastModified": "2026-06-13T07:53:09+00:00",
  "request_id": "bb49ce76-f01e-0051-4009-fb1da2000000",
  "request_server_encrypted": true,
  "structured_body": null,
  "version": "2026-04-06",
  "version_id": "2026-06-13T07:53:09.4420752Z"
}
==> Update (overwrite)
Finished[#############################################################]  100.0000%
{
  "client_request_id": "ec11862a-66fc-11f1-ad6f-acde48001122",
  "content_md5": "YjaKxXqV9ENp+EnUT5A7dA==",
  "date": "2026-06-13T07:53:09+00:00",
  "encryption_key_sha256": null,
  "encryption_scope": null,
  "etag": "\"0x8DEC920D058C2AB\"",
  "lastModified": "2026-06-13T07:53:10+00:00",
  "request_id": "a339913e-001e-0018-7809-fb5f49000000",
  "request_server_encrypted": true,
  "structured_body": null,
  "version": "2026-04-06",
  "version_id": "2026-06-13T07:53:10.4823460Z"
}
==> Read back
Finished[#############################################################]  100.0000%
{
  "container": "data",
  "content": "",
  "contentMd5": null,
  "deleted": false,
  "encryptedMetadata": null,
  "encryptionKeySha256": null,
  "encryptionScope": null,
  "hasLegalHold": null,
  "hasVersionsOnly": null,
  "immutabilityPolicy": {
    "expiryTime": null,
    "policyMode": null
  },
  "isAppendBlobSealed": null,
  "isCurrentVersion": true,
  "lastAccessedOn": null,
  "metadata": {},
  "name": "demo/hello.txt",
  "objectReplicationDestinationPolicy": null,
  "objectReplicationSourceProperties": [],
  "properties": {
    "appendBlobCommittedBlockCount": null,
    "blobTier": null,
    "blobTierChangeTime": null,
    "blobTierInferred": null,
    "blobType": "BlockBlob",
    "contentLength": 16,
    "contentRange": "bytes 0-15/16",
    "contentSettings": {
      "cacheControl": null,
      "contentDisposition": null,
      "contentEncoding": null,
      "contentLanguage": null,
      "contentMd5": "YjaKxXqV9ENp+EnUT5A7dA==",
      "contentType": "text/plain"
    },
    "copy": {
      "completionTime": null,
      "destinationSnapshot": null,
      "id": null,
      "incrementalCopy": null,
      "progress": null,
      "source": null,
      "status": null,
      "statusDescription": null
    },
    "creationTime": "2026-06-13T07:53:10+00:00",
    "deletedTime": null,
    "etag": "\"0x8DEC920D058C2AB\"",
    "lastModified": "2026-06-13T07:53:10+00:00",
    "lease": {
      "duration": null,
      "state": "available",
      "status": "unlocked"
    },
    "pageBlobSequenceNumber": null,
    "pageRanges": null,
    "rehydrationStatus": null,
    "remainingRetentionDays": null,
    "serverEncrypted": true
  },
  "rehydratePriority": null,
  "requestServerEncrypted": true,
  "snapshot": null,
  "tagCount": null,
  "tags": null,
  "versionId": "2026-06-13T07:53:10.4823460Z"
}
Downloaded content: updated content
==> Delete
==> Done
```

</details>

### Summary of operations

Each script performs four operations in sequence:

| Step      | AWS                     | GCP                             | Azure                                |
| --------- | ----------------------- | ------------------------------- | ------------------------------------ |
| Upload    | `aws s3 cp`             | `gcloud storage cp`             | `az storage blob upload`             |
| Update    | `aws s3 cp` (overwrite) | `gcloud storage cp` (overwrite) | `az storage blob upload --overwrite` |
| Read back | `aws s3 cp` (download)  | `gcloud storage cp` (download)  | `az storage blob download`           |
| Delete    | `aws s3 rm`             | `gcloud storage rm`             | `az storage blob delete`             |

The Azure script uses `--auth-mode login` so it honours your current `az login` identity rather than requiring a storage account key.
