# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 8-Rule Architecture

These rules apply to every task in this project unless explicitly overridden.
Bias: caution over speed on non-trivial work. Use judgment on trivial tasks.

### Rule 1 — Think Before Coding

State assumptions explicitly. If uncertain, ask rather than guess.
Push back when a simpler approach exists. Stop when confused.

### Rule 2 — Simplicity First

Minimum code that solves the problem. Nothing speculative.
No features beyond what was asked. No abstractions for single-use code.

### Rule 3 — Surgical Changes

Touch only what you must. Clean up only your own mess.
Don't "improve" adjacent code, comments, or formatting. Match existing style.

### Rule 4 — Goal-Driven Execution

Define success criteria. Loop until verified.
Don't follow steps. Define success and iterate independently.

### Rule 5 — Token budgets are not advisory

Per-task: 4,000 tokens. Per-session: 30,000 tokens.
If approaching budget, summarize and start fresh. Surface the breach. 

### Rule 6 — Read before you write

Before adding code, read exports, immediate callers, shared utilities.
If unsure why code is structured a certain way, ask.

### Rule 7 — Checkpoint after every significant step

Summarize what was done, what's verified, what's left.
Don't continue from a state you can't describe back. Stop and restate.

### Rule 8 — Fail loud

"Completed" is wrong if anything was skipped silently.
"Tests pass" is wrong if any were skipped.
Default to surfacing uncertainty, not hiding it.

## What this repo is

A mono-repo of standalone Terraform examples deployable to AWS, GCP, and Azure. Each subdirectory under `aws/`, `gcp/`, and `azure/` is a self-contained root module with its own `backend.tf`, `versions.tf`, `variables.tf`, `main.tf`, and `outputs.tf`. Modules are independent — there are no cross-module dependencies.

## Common commands

All Terraform commands must be run from inside the target module directory (e.g. `aws/object-storage/`):

```sh
terraform init
terraform fmt -check -recursive   # check formatting
terraform fmt -recursive           # fix formatting
terraform validate
terraform plan
terraform apply
```

Linting (run from the module directory — tflint reads `.tflint.hcl` configs from the repo root and the cloud-level directory):

```sh
tflint --init --chdir <module-path>
tflint --chdir <module-path>
```

Trigger CI manually via `gh`:

```sh
gh workflow run terraform.yml --field folder=aws/object-storage
gh workflow run smoke-test.yml --field cloud=aws   # aws | gcp | azure
gh workflow run test-cloud-auth.yml --field cloud=all
gh run watch
```

Update IAM permissions without re-running the full bootstrap:

```sh
./scripts/apply-aws-iam-policy.sh github-tf-public-cloud-plan  scripts/iam/aws-plan-policy.json
./scripts/apply-aws-iam-policy.sh github-tf-public-cloud-apply scripts/iam/aws-apply-policy.json
./scripts/apply-gcp-iam-bindings.sh [--remove] <sa-email> scripts/iam/gcp-permissions.json
./scripts/apply-azure-rbac.sh [--remove] <client-id> scripts/iam/azure-permissions.json
```

## Terraform version

Pinned to `1.15.5` via `.terraform-version` (used by tfenv/mise). All modules declare `>= 1.6, < 2.0`.

## Module structure conventions

Every root module follows this layout:

| File | Purpose |
|------|---------|
| `terraform.tf` | `terraform {}` block (required_version + required_providers + backend) and provider config |
| `variables.tf` | Input variables with descriptions and defaults |
| `main.tf` | Resources (or `data` sources for smoke-test modules) |
| `outputs.tf` | Outputs |

Provider versions: AWS `>= 5.0, < 7.0`, GCP `>= 6.0, < 7.0`, Azure `>= 4.0, < 5.0`.

Azure modules must pass `subscription_id` as a variable (injected via `TF_VAR_subscription_id` in CI) and set `skip_provider_registration = true` on the provider.

## tflint configuration

`.tflint.hcl` at the repo root enables the `terraform` plugin with the `recommended` preset. Each cloud directory has its own `.tflint.hcl` enabling the cloud-specific ruleset plugin (aws/google/azurerm). Both files are picked up automatically because tflint merges configs from parent directories.

## CI/CD overview

`.github/workflows/terraform.yml` runs on PRs and pushes to `main` for any `*.tf` change. It:

1. **detect** — finds the single changed Terraform module. PRs that touch multiple modules fail; pushes skip with a warning (use `workflow_dispatch` to target a specific module).
2. **validate** — `init`, `fmt -check`, `validate`, `tflint`.
3. **plan** — `terraform plan`, uploads the binary plan as an artifact, posts a collapsible comment on PRs.
4. **apply** — downloads the plan artifact and applies it (main branch push only).

Authentication uses OIDC — no long-lived credentials. The plan role (`AWS_PLAN_ROLE_ARN`) is used for validate/plan; the apply role (`AWS_ROLE_ARN`) is used for apply.

Composite actions in `.github/actions/`:
- `terraform-setup` — installs Terraform (reads `.terraform-version`) and delegates to `cloud-login`.
- `cloud-login` — performs OIDC authentication for the target cloud based on the `cloud` input.

## Smoke-test modules

`{cloud}/smoke-test/` modules contain only `data` sources (no resources). They verify that `terraform init` can reach the remote state backend and that `terraform plan` can resolve live provider data. Run via `smoke-test.yml`.

## Remote state backends

| Cloud | Backend | Bucket/Container |
|-------|---------|-----------------|
| AWS | S3 (`use_lockfile = true`, no DynamoDB) | `tf-public-cloud-aws-state-edo` |
| GCP | GCS | `tf-public-cloud-gcp-state-edo` |
| Azure | azurerm (`use_azuread_auth = true`) | storage account `tfpubliccloudazstate`, container `tfstate` |

## IAM permissions as code

Cloud IAM permissions live in `scripts/iam/` as JSON files and are applied with dedicated idempotent scripts. Edit the JSON, then re-run the apply script — do not modify permissions directly in the bootstrap scripts or in the cloud console.
