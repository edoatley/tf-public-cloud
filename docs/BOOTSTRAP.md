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

## Identity model

All three clouds use the same pattern: two separate identities — one for plan (read-only) and one for
apply (write). Both are gated through GitHub environments:

| Environment | Purpose | Identity |
| ----------- | ------- | -------- |
| `default` | plan — runs on any branch, PR, or dispatch | read-only role / SA / app |
| `production` | apply / destroy — gated by reviewer approval and `release-*` tag restriction | write role / SA / app |

The environment gate and the cloud IAM trust condition are independent controls. Both must pass before
write credentials are issued.

## AWS Bootstrap

### Step 1a - Run the bootstrap script

`scripts/bootstrap/bootstrap-aws.sh` handles everything in one go:

- Creates the S3 state bucket with versioning, SSE-AES256, public-access-block, and HTTPS-only bucket policy
- State locking uses S3 native locking (`use_lockfile = true`) — no DynamoDB table is required
- Creates the GitHub Actions OIDC Identity Provider (`token.actions.githubusercontent.com`) if not already present
- Creates two IAM roles:
  - `github-tf-public-cloud-plan` — broad wildcard trust (`repo:org/repo:*`), read-only permissions; used for validate and plan jobs running in the `default` environment
  - `github-tf-public-cloud-apply` — scoped to `environment:production` in the trust policy; used for apply and destroy jobs running in the `production` environment
- Applies inline policies from `scripts/iam/aws-plan-policy.json` and `scripts/iam/aws-apply-policy.json` via `scripts/bootstrap/apply-aws-iam-policy.sh`

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
- Creates a Workload Identity Pool (`github-pool`) and OIDC Provider (`github-provider`) with attribute
  mapping for `repository`, `ref`, and `environment` claims
- Creates two Service Accounts:
  - `github-actions-tf-plan` — WIF binding scoped to the repository (`attribute.repository`), allowing any branch or dispatch; read-only permissions
  - `github-actions-tf-apply` — WIF binding scoped to `attribute.environment/production`, trusting only tokens issued for the `production` GitHub environment; write permissions
- Sets `GCP_SERVICE_ACCOUNT` as an environment-level variable in GitHub automatically:
  - `default` environment → plan SA
  - `production` environment → apply SA
- Applies IAM bindings from `scripts/iam/gcp-plan-permissions.json` and `scripts/iam/gcp-apply-permissions.json`

```sh
./scripts/bootstrap/bootstrap-gcp.sh
```

The script prints all values you need for `backend.tf` and GitHub Variables at the end.

To update permissions later, edit the relevant JSON file and re-run:

```sh
# Plan SA
./scripts/bootstrap/apply-gcp-iam-bindings.sh \
  github-actions-tf-plan@gcp-sandbox-2026-18798.iam.gserviceaccount.com \
  scripts/iam/gcp-plan-permissions.json

# Apply SA
./scripts/bootstrap/apply-gcp-iam-bindings.sh \
  github-actions-tf-apply@gcp-sandbox-2026-18798.iam.gserviceaccount.com \
  scripts/iam/gcp-apply-permissions.json
```

### Step 2b. Set GitHub Variables for GCP

```sh
gh variable set GCP_WIF_PROVIDER --body "projects/116498173042/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
gh variable set GCP_PROJECT_ID   --body "gcp-sandbox-2026-18798"
```

`GCP_SERVICE_ACCOUNT` is set per-environment automatically by the bootstrap script.

## Azure Bootstrap

### Step 3a. Run the bootstrap script

`scripts/bootstrap/bootstrap-azure.sh` handles everything in one go:

- Registers required resource providers if not already enabled on the subscription
- Creates the Resource Group, Storage Account (HTTPS-only, TLS 1.2, versioning enabled), and Blob Container for Terraform state
- Creates the examples Resource Group
- Creates two App Registrations and Service Principals:
  - `github-tf-public-cloud-plan` — federated credential for `environment:default`; read-only RBAC (Reader on subscription + Storage Blob Data Contributor on state account)
  - `github-tf-public-cloud-apply` — federated credential for `environment:production`; write RBAC (Contributor + AcrPush on subscription + Storage Blob Data Contributor on state account)
- Creates `default` and `production` GitHub environments if they do not exist
- Sets `AZURE_CLIENT_ID` as an environment-level variable in GitHub automatically:
  - `default` environment → plan app client ID
  - `production` environment → apply app client ID

```sh
./scripts/bootstrap/bootstrap-azure.sh
```

The script prints all values you need for `backend.tf` and GitHub Variables at the end.

To update permissions later, edit the relevant JSON file and re-run:

```sh
# Plan app
./scripts/bootstrap/apply-azure-rbac.sh <plan-client-id> scripts/iam/azure-plan-permissions.json

# Apply app
./scripts/bootstrap/apply-azure-rbac.sh <apply-client-id> scripts/iam/azure-apply-permissions.json
```

### Step 3b. Set GitHub Variables for Azure

```sh
gh variable set AZURE_TENANT_ID       --body "YOUR_TENANT_ID"
gh variable set AZURE_SUBSCRIPTION_ID --body "YOUR_SUBSCRIPTION_ID"
```

`AZURE_CLIENT_ID` is set per-environment automatically by the bootstrap script.

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

Once bootstrapped, run the smoke test via `plan-resource.yml` to confirm that GitHub Actions can
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
gh workflow run plan-resource.yml \
  --field resource_type=smoke-test \
  --field cloud=aws \
  --field action=plan

# Smoke-test all three clouds at once
gh workflow run plan-resource.yml \
  --field resource_type=smoke-test \
  --field cloud=all \
  --field action=plan

# Watch the latest run
gh run list --workflow=plan-resource.yml --limit=1
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
| GCP (plan SA) | `scripts/iam/gcp-plan-permissions.json` | `scripts/bootstrap/apply-gcp-iam-bindings.sh` | Additive — use `--remove` to remove listed bindings |
| GCP (apply SA) | `scripts/iam/gcp-apply-permissions.json` | `scripts/bootstrap/apply-gcp-iam-bindings.sh` | Additive — use `--remove` to remove listed bindings |
| Azure (plan app) | `scripts/iam/azure-plan-permissions.json` | `scripts/bootstrap/apply-azure-rbac.sh` | Idempotent apply — use `--remove` to delete listed assignments |
| Azure (apply app) | `scripts/iam/azure-apply-permissions.json` | `scripts/bootstrap/apply-azure-rbac.sh` | Idempotent apply — use `--remove` to delete listed assignments |

**To add a permission:** add an entry to the relevant JSON file and re-run the apply script.

**To remove a permission:**

- *AWS*: delete the statement from the policy JSON and re-run `apply-aws-iam-policy.sh` — the whole policy is replaced atomically.
- *GCP*: delete the entry from the permissions JSON and re-run `apply-gcp-iam-bindings.sh --remove`.
- *Azure*: delete the entry from the permissions JSON and re-run `apply-azure-rbac.sh --remove <client-id> <file>`.
