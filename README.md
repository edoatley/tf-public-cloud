# tf-public-cloud

A mono-repo of standalone Terraform examples across AWS, GCP, and Azure. Each example is a self-contained root module that can be deployed independently.

## Structure

```
tf-public-cloud/
├── scripts/
│   ├── bootstrap/    # Cloud bootstrap and IAM apply scripts
│   ├── examples/     # Manual resource deploy/teardown scripts
│   ├── hooks/        # Git hooks (pre-commit)
│   └── tools/        # On-demand tools (trivy)
│   └── iam/          # IAM permission JSON files
├── docs/             # Setup guide and documentation
├── aws/              # AWS Terraform examples
├── gcp/              # GCP Terraform examples
└── azure/            # Azure Terraform examples
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6 (use [tfenv](https://github.com/tfutils/tfenv) — a `.terraform-version` file is provided)
- AWS `aws` CLI, Google `gcloud` CLI, and/or Azure `az` CLI (depending on which cloud(s) you are targeting)
- (Optional) [trivy](https://github.com/aquasecurity/trivy) — IaC misconfiguration scanning (`brew install trivy`)
- (Optional) [tflint](https://github.com/terraform-linters/tflint) - terraform linting
- (Optional) Github `gh` CLI to set variables & trigger workflows

## Getting started

1. Read `docs/BOOTSTRAP.md` for the full one-time setup guide (state backends, OIDC, GitHub Variables).
2. Trigger the GitHub Actions workflow to validate, plan, and apply an example module:

```sh
gh workflow run terraform.yml --field folder=aws/object-storage
gh run watch
```

## GitHub Actions Workflows

| Workflow | File | Description |
| -------- | ---- | ----------- |
| Terraform CI | `terraform.yml` | Validates all changed modules in parallel on PRs and pushes to `main` (`init`, `fmt`, `validate`, `tflint`). Also runs a Trivy IaC + secrets scan. Use `workflow_dispatch` with a `folder` input to target a specific module manually. |
| Plan Resource | `plan-resource.yml` | Runs `terraform plan` for a named resource type against one or all clouds via `workflow_dispatch`. Uses read-only credentials — safe to run on any branch. Use `resource_type=smoke-test` to verify OIDC auth and remote state connectivity. |
| Apply Resource | `apply-resource.yml` | Applies or destroys a named resource type against one or all clouds via `workflow_dispatch`. Requires approval via the `production` GitHub environment — write credentials are only issued after the gate is passed. |
| Build and Push | `build-and-push.yml` | Builds the Spring Boot container image and pushes it to each cloud's container registry. Run this after applying `container-registry` and before applying `containerised-app`. |

All workflows authenticate via OIDC — no long-lived credentials. See `docs/BOOTSTRAP.md` for the required GitHub Actions Variables,
and [docs/gcp-authentication.md](docs/gcp-authentication.md) for a step-by-step account of the GCP token exchange.

## Examples

| Example              | AWS                                                   | GCP                                                   | Azure                                                     | Docs                                                               |
| -------------------- | ----------------------------------------------------- | ----------------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------ |
| object-storage       | [aws/object-storage](aws/object-storage/)             | [gcp/object-storage](gcp/object-storage/)             | [azure/object-storage](azure/object-storage/)             | [docs/object-storage.md](docs/object-storage.md)                  |
| virtual-machine      | [aws/virtual-machine](aws/virtual-machine/)           | [gcp/virtual-machine](gcp/virtual-machine/)           | [azure/virtual-machine](azure/virtual-machine/)           | [docs/virtual-machines.md](docs/virtual-machines.md)              |
| container-registry   | [aws/container-registry](aws/container-registry/)     | [gcp/container-registry](gcp/container-registry/)     | [azure/container-registry](azure/container-registry/)     | [docs/containerised-app.md](docs/containerised-app.md)            |
| containerised-app    | [aws/containerised-app](aws/containerised-app/)       | [gcp/containerised-app](gcp/containerised-app/)       | [azure/containerised-app](azure/containerised-app/)       | [docs/containerised-app.md](docs/containerised-app.md)            |
| private-service-connect | —                                                  | [gcp/private-service-connect](gcp/private-service-connect/) | —                                                     | [docs/private-service-connect.md](docs/private-service-connect.md) |
