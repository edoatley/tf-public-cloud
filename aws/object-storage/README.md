# AWS: Object Storage (S3)

Creates a hardened S3 bucket with:

- Versioning enabled
- Server-side encryption (SSE-S3 by default; SSE-KMS optionally)
- All public access blocked
- Bucket policy enforcing HTTPS-only access

## Usage

1. Complete the [bootstrap guide](../../docs/BOOTSTRAP.md) for AWS.
2. Fill in `backend.tf` with the values printed by `bootstrap-aws.sh`.
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
| `bucket_name` | Globally unique S3 bucket name | `string` | — | yes |
| `region` | AWS region | `string` | `eu-west-2` | no |
| `enable_kms` | Use SSE-KMS instead of SSE-S3 | `bool` | `false` | no |
| `kms_key_arn` | ARN of existing KMS key (required when `enable_kms = true`) | `string` | `null` | no |
| `tags` | Tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_name` | Name of the S3 bucket |
| `bucket_arn` | ARN of the S3 bucket |
| `bucket_regional_domain_name` | Regional domain name |
