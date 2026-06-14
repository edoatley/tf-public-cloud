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
| Deploy Resource | `deploy-resource.yml` | Plans, applies, or destroys a named resource type (e.g. `object-storage`, `virtual-machine`, `smoke-test`) against one or all clouds via `workflow_dispatch`. Use `resource_type=smoke-test action=plan` to verify OIDC auth and remote state connectivity. |

All workflows authenticate via OIDC — no long-lived credentials. See `docs/BOOTSTRAP.md` for the required GitHub Actions Variables.

## Examples

| Example         | AWS                                         | GCP                                         | Azure                                           | Docs                                               |
| --------------- | ------------------------------------------- | ------------------------------------------- | ----------------------------------------------- | -------------------------------------------------- |
| object-storage  | [aws/object-storage](aws/object-storage/)   | [gcp/object-storage](gcp/object-storage/)   | [azure/object-storage](azure/object-storage/)   | [docs/object-storage.md](docs/object-storage.md)  |
| virtual-machine | [aws/virtual-machine](aws/virtual-machine/) | [gcp/virtual-machine](gcp/virtual-machine/) | [azure/virtual-machine](azure/virtual-machine/) | [docs/virtual-machines.md](docs/virtual-machines.md) |
