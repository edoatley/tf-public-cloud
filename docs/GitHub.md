# GitHub Actions: Variables, Environments, and Workflows

## Environments

Two GitHub environments gate write access to cloud infrastructure.

| Environment  | Purpose               | Who can use it                                                    |
| ------------ | --------------------- | ----------------------------------------------------------------- |
| `default`    | Plan/read-only access | Any workflow job that reads state or runs `terraform plan`        |
| `production` | Apply/write access    | Workflow jobs that mutate infrastructure or push container images |

Environment membership controls which cloud credentials a job receives (see Variables below). It also controls the OIDC token claims that cloud providers verify — jobs without an environment declaration cannot authenticate as apply-level identities.

---

## Variables

### Repo-level (available to all jobs)

| Variable                | Value                                                         | Purpose                                                                 |
| ----------------------- | ------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `AWS_REGION`            | `eu-west-2`                                                   | AWS region for all resources                                            |
| `AWS_PLAN_ROLE_ARN`     | `arn:aws:iam::793976186123:role/github-tf-public-cloud-plan`  | IAM role assumed for validate/plan steps                                |
| `AWS_ROLE_ARN`          | `arn:aws:iam::793976186123:role/github-tf-public-cloud-apply` | IAM role assumed for apply/destroy steps                                |
| `AZURE_SUBSCRIPTION_ID` | `edbc314c-...`                                                | Azure subscription targeted by all modules                              |
| `AZURE_TENANT_ID`       | `f20d4ab3-...`                                                | Azure AD tenant for OIDC federation                                     |
| `GCP_PROJECT_ID`        | `gcp-sandbox-2026-18798`                                      | GCP project targeted by all modules                                     |
| `GCP_WIF_PROVIDER`      | `projects/116498173042/.../github-provider`                   | Workload Identity Federation provider used by both GCP service accounts |
| `SSH_PUBLIC_KEY`        | base64-encoded RSA public key                                 | Injected as `TF_VAR_ssh_public_key_b64` for virtual-machine modules     |

### Environment: `default` (plan / read-only)

| Variable              | Value                        | Purpose                                                                          |
| --------------------- | ---------------------------- | -------------------------------------------------------------------------------- |
| `AZURE_CLIENT_ID`     | `9343b2c9-...`               | App registration authorised for plan-only Azure operations                       |
| `GCP_SERVICE_ACCOUNT` | `github-actions-tf-plan@...` | GCP service account trusted for any repo token (no environment condition on WIF) |

### Environment: `production` (apply / write)

| Variable              | Value                         | Purpose                                                                                                     |
| --------------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `AZURE_CLIENT_ID`     | `acc8446a-...`                | App registration authorised for apply-level Azure operations                                                |
| `GCP_SERVICE_ACCOUNT` | `github-actions-tf-apply@...` | GCP service account trusted only for tokens carrying `attribute.environment=production` on the WIF provider |

### Why AWS has no environment-level variables

AWS uses two separate IAM roles (`AWS_PLAN_ROLE_ARN` / `AWS_ROLE_ARN`) stored at repo level. Each workflow explicitly chooses which role to pass to the `cloud-login` action, so no environment override is needed.

### Why GCP_SERVICE_ACCOUNT is environment-scoped

The GCP Workload Identity Federation provider maps the GitHub OIDC `environment` claim. The apply SA binding carries an `attribute.environment/production` condition — it will reject tokens from jobs not in the `production` environment. Jobs in `default` use the plan SA, which has no environment condition (only a repository condition). This means any job that omits an environment declaration would silently fall back to repo-level — which is why the repo-level `GCP_SERVICE_ACCOUNT` variable has been removed to prevent that silent fallback.

---

## Workflows

### `terraform.yml` — PR validation

Triggered by pull requests and pushes to `main` for any `*.tf` change.

**Jobs:** detect → validate, plus trivy in parallel

- **detect**: finds the single changed module. PRs touching multiple modules fail; pushes skip with a warning.
- **validate**: `terraform init`, `fmt -check`, `validate`, `tflint`. Uses `environment: default`.
- **trivy**: `config` and `secret` scan across the whole repo. Writes findings to the job summary and posts a count comment on PRs. Does not depend on `detect`, so it also runs on PRs that touch no Terraform.

This workflow validates only — it never plans or applies. Use `plan-resource.yml` and `apply-resource.yml` for that.

### `plan-resource.yml` — Manual plan for a specific module

`workflow_dispatch` only. Inputs: `resource_type`, `cloud`.

Runs plan across the selected cloud(s) for a named resource type. Uses `environment: default` on all jobs. Useful for previewing changes on a feature branch before triggering apply.

### `apply-resource.yml` — Manual apply, destroy or preflight for a specific module

`workflow_dispatch` only. Inputs: `resource_type`, `cloud`, `action` (apply/destroy/preflight).

Runs Terraform across the selected cloud(s). All jobs use `environment: production`. Must be triggered from a `release-*` tag — the production environment's deployment branch policy lists a tag pattern only, so any branch, `main` included, is rejected.

| `action` | What runs |
| -------- | --------- |
| `apply` | `terraform apply`, then the module's verification script |
| `destroy` | `terraform destroy` |
| `preflight` | `terraform apply`, the verification script, then `terraform destroy` — always, even when the verification fails |

**Verification.** After an apply, the job runs `scripts/examples/<resource_type>/<cloud>.sh` if it exists and fails the job when the script exits non-zero, so a green run means the module works rather than merely that Terraform succeeded. A module with no script for that cloud is reported as a GitHub warning annotation and in the step summary as **Not verified** — never as a pass. The script's last 60 lines are written to the step summary either way.

**Preflight** exists for proving a new or substantially reworked module before cutting a release tag. The teardown step carries `if: always()`, so a failed verification still destroys rather than leaking resources; the job's own result reflects the verification, not the teardown. It reuses `environment: production` and therefore still needs a `release-*` tag.

### `build-and-push.yml` — Build and push container image

`workflow_dispatch` only. Inputs: `cloud`, `image_tag` (default: `latest`).

Builds the Docker image from `app/` and pushes it to the registry for each selected cloud:

| Cloud | Registry                                                                        |
| ----- | ------------------------------------------------------------------------------- |
| AWS   | ECR — repository `tf-public-cloud-app`                                          |
| GCP   | Artifact Registry — `europe-west2-docker.pkg.dev/<project>/tf-public-cloud-app` |
| Azure | ACR — `tfpubcloudacredoatley`                                                   |

All three jobs use `environment: production` so they authenticate with write-level credentials. Must be triggered from a `release-*` ref. Run this before `apply-resource.yml` for `containerised-app` — the Terraform module references the image by tag.

---

## Composite Actions

### `.github/actions/terraform-setup`

Installs Terraform (reads version from `.terraform-version`) then delegates to `cloud-login`.

### `.github/actions/cloud-login`

Performs OIDC authentication for `aws`, `gcp`, or `azure`. Also sets `ARM_*` environment variables for the Azure Terraform provider.

### `.github/actions/terraform-run`

Runs `terraform init`, then the requested action (`plan` or `apply`/`destroy`) against a given `module_path`.

---

## Deployment order for containerised-app

The containerised-app modules depend on a container image existing in the registry before Terraform runs (the image URI is referenced in the module). The correct order is:

1. `apply-resource.yml` — `resource_type=container-registry`, `cloud=all` — provisions the registries.
2. `build-and-push.yml` — `cloud=all` — builds and pushes the image.
3. `apply-resource.yml` — `resource_type=containerised-app`, `cloud=all` — deploys the app infrastructure.
