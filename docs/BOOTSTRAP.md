# Bootstrap Guide

This guide covers every step required to go from zero to a fully working deployment pipeline.
Complete the relevant cloud section(s) once before running `terraform init` in any example module.

## Table of Contents

- [Prerequisites](#prerequisites)
- [AWS Bootstrap](#aws-bootstrap)
- [GCP Bootstrap](#gcp-bootstrap)
- [Azure Bootstrap](#azure-bootstrap)
- [Post-Bootstrap: Update backend.tf files](#post-bootstrap-update-backendtf-files)
- [Verify OIDC authentication and Terraform connectivity](#verify-oidc-authentication-and-terraform-connectivity)
- [Managing permissions](#managing-permissions)

## Prerequisites

The following tools must be installed before running any bootstrap script.

| Tool | Min version | Purpose | Install |
| ---- | ----------- | ------- | ------- |
| `terraform` | 1.6 | Provisions cloud resources | `brew install tfenv` - a `.terraform-version` file is used to set the version to be used |
| `tflint` | 0.50+ | Lints Terraform code in CI | `brew install tflint` |
| `trivy` | latest | IaC misconfiguration scanning (local, on-demand) | `brew install trivy` |
| `aws` CLI | 2.x | AWS bootstrap and auth | `brew install awscli` |
| `gcloud` CLI | latest | GCP bootstrap and auth | `brew install --cask google-cloud-sdk` |
| `az` CLI | 2.50+ | Azure bootstrap and auth | `brew install azure-cli` |
| `gh` CLI | 2.x | Sets GitHub Actions Variables | `brew install gh` |
| `python3` | 3.8+ | Used internally by GCP and Azure scripts | pre-installed on macOS |

Authenticate each CLI before running the bootstrap scripts. Only authenticate the cloud(s) you intend to use.

```sh
# AWS — verify the sandbox profile works
aws sts get-caller-identity --profile sandbox

# GCP — interactive browser login, then application-default credentials for local tools
gcloud auth login
gcloud auth application-default login

# Azure — interactive browser login
az login

# GitHub — interactive browser or token login
gh auth login
```

> [!NOTE]
> If any of these fail you may need to sign up for an account with the cloud provider, discussion of this is outside the
> scope of this repository.

## AWS Bootstrap

### Step 1a - Run the bootstrap script

`scripts/bootstrap/bootstrap-aws.sh` handles everything in one go:

- Creates the S3 state bucket with versioning, SSE-AES256, public-access-block, and HTTPS-only bucket policy
- State locking uses S3 native locking (`use_lockfile = true`) — no DynamoDB table is required
- Creates the GitHub Actions OIDC Identity Provider (`token.actions.githubusercontent.com`) if not already present
- Creates two IAM roles, both trusted for any branch/event in this repo (`repo:edoatley/tf-public-cloud:*`):
  - `github-tf-public-cloud-plan` — used for `validate` and `plan` jobs
  - `github-tf-public-cloud-apply` — used for `apply` jobs (apply is gated in the workflow to `main` pushes only, not in the trust policy)
- Applies inline policies from `scripts/iam/aws-plan-policy.json` and `scripts/iam/aws-apply-policy.json` via `scripts/bootstrap/apply-aws-iam-policy.sh`

All resource names are pre-configured for this repo. Edit the variables at the top of the script if you need to change them.
The script uses the `sandbox` AWS CLI profile by default (override with `AWS_PROFILE=myprofile ./scripts/bootstrap/bootstrap-aws.sh`).

```sh
./scripts/bootstrap/bootstrap-aws.sh
```

The script prints all values you need for `backend.tf` and GitHub Variables at the end.

To update permissions later, edit the relevant JSON file and re-run:

```sh
./scripts/bootstrap/apply-aws-iam-policy.sh github-tf-public-cloud-plan  scripts/iam/aws-plan-policy.json
./scripts/bootstrap/apply-aws-iam-policy.sh github-tf-public-cloud-apply scripts/iam/aws-apply-policy.json
```

### Step 1b. Set GitHub Variables for AWS

```sh
gh variable set AWS_ROLE_ARN      --body "arn:aws:iam::793976186123:role/github-tf-public-cloud-apply"
gh variable set AWS_PLAN_ROLE_ARN --body "arn:aws:iam::793976186123:role/github-tf-public-cloud-plan"
gh variable set AWS_REGION        --body "eu-west-2"
```

## GCP Bootstrap

### Step 2a. Run the bootstrap script

`scripts/bootstrap/bootstrap-gcp.sh` handles everything in one go:

- Enables required GCP APIs: `iamcredentials`, `sts`, `cloudresourcemanager`, `storage`, `iam`
- Creates the GCS state bucket with uniform access, versioning, and public access prevention
- Creates a Workload Identity Pool (`github-pool`) and OIDC Provider (`github-provider`) for GitHub Actions
- Creates the `github-actions-tf` Service Account
- Binds the Workload Identity Provider to the Service Account
- Applies IAM bindings from `scripts/iam/gcp-permissions.json` via `scripts/bootstrap/apply-gcp-iam-bindings.sh`

All resource names are pre-configured for this repo. Edit the variables at the top of the script if you need to change them.

```sh
./scripts/bootstrap/bootstrap-gcp.sh
```

The script prints all values you need for `backend.tf` and GitHub Variables at the end.

To update permissions later, edit `scripts/iam/gcp-permissions.json` and re-run:

```sh
# Add bindings
./scripts/bootstrap/apply-gcp-iam-bindings.sh \
  github-actions-tf@gcp-sandbox-2026-18798.iam.gserviceaccount.com \
  scripts/iam/gcp-permissions.json

# Remove bindings (e.g. after removing entries from the JSON file)
./scripts/bootstrap/apply-gcp-iam-bindings.sh --remove \
  github-actions-tf@gcp-sandbox-2026-18798.iam.gserviceaccount.com \
  scripts/iam/gcp-permissions.json
```

### Step 2b. Set GitHub Variables for GCP

```sh
gh variable set GCP_WIF_PROVIDER    --body "projects/116498173042/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
gh variable set GCP_SERVICE_ACCOUNT --body "github-actions-tf@gcp-sandbox-2026-18798.iam.gserviceaccount.com"
gh variable set GCP_PROJECT_ID      --body "gcp-sandbox-2026-18798"   
```

## Azure Bootstrap

### Step 3a. Run the bootstrap script

`scripts/bootstrap/bootstrap-azure.sh` handles everything in one go:

- Registers the `Microsoft.Storage`, `Microsoft.Authorization`, `Microsoft.Network`, `Microsoft.Compute`, `Microsoft.ContainerRegistry`, and `Microsoft.App` resource providers if not already enabled on the subscription
- Creates the Resource Group, Storage Account (HTTPS-only, TLS 1.2, versioning enabled), and Blob Container for Terraform state
- Creates the examples Resource Group
- Creates an App Registration and Service Principal for GitHub Actions OIDC authentication
- Creates a `default` GitHub Actions environment in the repository (required for the federated credential)
- Adds a single Federated Credential `GHA-Default-Creds` scoped to `environment:default`, which covers all branches and pull requests — Azure does not support wildcard subjects spanning multiple colon-separated segments (`repo:org/repo:*` does not match branch subjects), so an environment credential is the correct approach
- Assigns RBAC roles from `scripts/iam/azure-permissions.json` via `scripts/bootstrap/apply-azure-rbac.sh`

All resource names are pre-configured for this repo. Edit the variables at the top of the script if you need to change them. You must be authenticated as an Owner (or equivalent) on the target subscription.

```sh
./scripts/bootstrap/bootstrap-azure.sh
```

The script prints all values you need for `backend.tf` and GitHub Variables at the end.

To update permissions later, edit `scripts/iam/azure-permissions.json` and re-run:

```sh
# Add assignments
./scripts/bootstrap/apply-azure-rbac.sh <client-id> scripts/iam/azure-permissions.json

# Remove assignments
./scripts/bootstrap/apply-azure-rbac.sh --remove <client-id> scripts/iam/azure-permissions.json
```

### Step 3b. Set GitHub Variables for Azure

```sh
gh variable set AZURE_CLIENT_ID       --body "YOUR_CLIENT_ID"
gh variable set AZURE_TENANT_ID       --body "YOUR_TENANT_ID"
gh variable set AZURE_SUBSCRIPTION_ID --body "YOUR_SUBSCRIPTION_ID"
```

Use the values printed at the end of `bootstrap-azure.sh`.

## Post-Bootstrap: Update backend.tf files

After running each bootstrap script, fill in the real values it prints into the corresponding `backend.tf` for each module. The key/prefix must be unique per module — examples below use `aws/object-storage` but the same pattern applies to every module under that cloud.

### AWS — e.g. `aws/object-storage/terraform.tf`

```hcl
terraform {
  backend "s3" {
    bucket       = "tf-public-cloud-aws-state-edo"
    key          = "aws/object-storage/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
```

### GCP — e.g. `gcp/object-storage/terraform.tf`

```hcl
terraform {
  backend "gcs" {
    bucket = "tf-public-cloud-gcp-state-edo"
    prefix = "gcp/object-storage"
  }
}
```

### Azure — e.g. `azure/object-storage/terraform.tf`

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tf-public-cloud-state"
    storage_account_name = "tfpubliccloudazstate"
    container_name       = "tfstate"
    key                  = "azure/object-storage/terraform.tfstate"
    use_azuread_auth     = true
  }
}
```

## Verify OIDC authentication and Terraform connectivity

Once bootstrapped, run the smoke test via `deploy-resource.yml` to confirm that GitHub Actions can
authenticate to each cloud via OIDC and that Terraform can reach the remote state backend and
resolve live data sources. The smoke-test modules live in `{cloud}/smoke-test/` and contain only
`data` sources — no resources are created.

A successful run proves:

- OIDC token exchange works and the correct identity is assumed
- `terraform init` can authenticate to and read the remote state bucket
- The cloud provider can resolve real account/project/subscription metadata
- `terraform plan` completes cleanly end-to-end

```sh
# Smoke-test a single cloud
gh workflow run deploy-resource.yml \
  --field resource_type=smoke-test \
  --field cloud=aws \
  --field action=plan

# Smoke-test all three clouds at once
gh workflow run deploy-resource.yml \
  --field resource_type=smoke-test \
  --field cloud=all \
  --field action=plan

# Watch the latest run
gh run list --workflow=deploy-resource.yml --limit=1
gh run watch
```

The job summary reports which backend was initialised and confirms the plan succeeded.

### What the smoke test checks per cloud

| Cloud | Data sources | Confirms |
| ----- | ------------ | -------- |
| AWS | `aws_caller_identity`, `aws_region`, `aws_partition` | Role ARN, account ID, region |
| GCP | `google_project`, `google_client_openid_userinfo` | Project ID/number, service account email |
| Azure | `azurerm_subscription`, `azurerm_client_config` | Subscription ID/name, tenant ID, object ID |

## Managing permissions

Permissions for each cloud are stored as JSON files in `scripts/iam/` and applied with dedicated scripts.
This keeps permissions reviewable as a diff rather than buried in shell logic.

| Cloud | Permissions file | Apply script | Notes |
| ----- | ---------------- | ------------ | ----- |
| AWS (plan role) | `scripts/iam/aws-plan-policy.json` | `scripts/bootstrap/apply-aws-iam-policy.sh` | Replaces the full inline policy on each run |
| AWS (apply role) | `scripts/iam/aws-apply-policy.json` | `scripts/bootstrap/apply-aws-iam-policy.sh` | Replaces the full inline policy on each run |
| GCP | `scripts/iam/gcp-permissions.json` | `scripts/bootstrap/apply-gcp-iam-bindings.sh` | Additive — use `--remove` to remove listed bindings |
| Azure | `scripts/iam/azure-permissions.json` | `scripts/bootstrap/apply-azure-rbac.sh` | Idempotent apply — use `--remove` to delete listed assignments |

**To add a permission:** add an entry to the relevant JSON file and re-run the apply script.

**To remove a permission:**

- *AWS*: delete the statement from the policy JSON and re-run `apply-aws-iam-policy.sh` — the whole policy is replaced atomically.
- *GCP*: delete the entry from `gcp-permissions.json` and re-run `apply-gcp-iam-bindings.sh --remove`.
- *Azure*: delete the entry from `azure-permissions.json` and re-run `scripts/bootstrap/apply-azure-rbac.sh --remove <client-id> scripts/iam/azure-permissions.json`.
