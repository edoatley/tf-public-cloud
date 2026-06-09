# GCP: Object Storage (GCS)

Creates a hardened Cloud Storage bucket with:

- Uniform bucket-level access (IAM-only, no per-object ACLs)
- Public access prevention enforced
- Versioning enabled
- Optional CMEK encryption via Cloud KMS

## Usage

1. Complete the [bootstrap guide](../../docs/BOOTSTRAP.md) for GCP.
2. Fill in `backend.tf` with the bucket name printed by `bootstrap-gcp.sh`.
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
| `project` | GCP project ID | `string` | — | yes |
| `region` | GCP region | `string` | `europe-west2` | no |
| `bucket_name` | Globally unique bucket name | `string` | — | yes |
| `kms_key_name` | Cloud KMS key resource name for CMEK | `string` | `null` | no |
| `labels` | Labels applied to the bucket | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_name` | Name of the GCS bucket |
| `bucket_url` | `gs://` URL |
| `bucket_self_link` | Self-link URI |
