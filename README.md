# tf-public-cloud

A mono-repo of standalone Terraform examples across AWS, GCP, and Azure. Each example is a self-contained root module that can be deployed independently.

## Structure

```
tf-public-cloud/
├── scripts/          # Bootstrap scripts
├── docs/             # Setup guide and documentation
├── aws/              # AWS Terraform examples
├── gcp/              # GCP Terraform examples
└── azure/            # Azure Terraform examples
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6 (use [tfenv](https://github.com/tfutils/tfenv) or [mise](https://mise.jdx.dev/) to manage versions — a `.terraform-version` file is provided)
- [tflint](https://github.com/terraform-linters/tflint)
- AWS CLI, gcloud CLI, and/or Azure CLI depending on which cloud you are targeting

## Getting started

1. Read `docs/BOOTSTRAP.md` for the full one-time setup guide (state backends, OIDC, GitHub Variables).
2. Navigate to an example folder and run:
   ```sh
   terraform init
   terraform plan
   terraform apply
   ```

## CI/CD

A single GitHub Actions workflow (`.github/workflows/terraform.yml`) handles all three clouds. It authenticates via OIDC (no long-lived credentials), runs `validate` + `plan` on PRs, and auto-applies on merge to `main`.

See `docs/BOOTSTRAP.md` for the required GitHub Actions Variables.

## Examples

| Example | AWS | GCP | Azure | Docs |
|---------|-----|-----|-------|------|
| object-storage | [aws/object-storage](aws/object-storage/) | [gcp/object-storage](gcp/object-storage/) | [azure/object-storage](azure/object-storage/) | [docs/object-storage.md](docs/object-storage.md) |
