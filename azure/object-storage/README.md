# Azure: Object Storage (Blob Storage)

Creates a hardened Azure Storage Account with a private Blob Container:

- HTTPS-only traffic enforced
- Minimum TLS version: 1.2
- Public blob access disabled
- Blob versioning enabled
- Soft-delete retention (7 days) for blobs and containers

## Usage

1. Complete the [bootstrap guide](../../docs/BOOTSTRAP.md) for Azure.
2. Fill in `backend.tf` with the values printed by `bootstrap-azure.sh`.
3. Copy `terraform.tfvars.example` to `terraform.tfvars` and edit values.
4. Run:
   ```sh
   terraform init
   terraform plan
   terraform apply
   ```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `subscription_id` | Azure subscription ID | `string` | — | yes |
| `resource_group_name` | Resource group to create | `string` | — | yes |
| `location` | Azure region | `string` | `uksouth` | no |
| `storage_account_name` | Storage account name (globally unique, 3-24 alphanumeric) | `string` | — | yes |
| `container_name` | Blob container name | `string` | `data` | no |
| `account_replication_type` | Replication type (LRS, GRS, ZRS…) | `string` | `LRS` | no |
| `tags` | Tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `storage_account_name` | Name of the storage account |
| `storage_account_id` | Resource ID |
| `container_name` | Name of the blob container |
| `primary_blob_endpoint` | Primary blob endpoint URL |
