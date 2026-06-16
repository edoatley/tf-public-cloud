# Serverless

- [Serverless](#serverless)
  - [Introduction](#introduction)
    - [What each example provisions](#what-each-example-provisions)
  - [Concepts and terminology](#concepts-and-terminology)
    - [FaaS vs containers](#faas-vs-containers)
    - [Packaging and deployment](#packaging-and-deployment)
    - [Cold starts](#cold-starts)
    - [Scaling and cost](#scaling-and-cost)
  - [The function](#the-function)
  - [AWS — Lambda + Function URL](#aws--lambda--function-url)
    - [`aws/serverless`](#awsserverless)
  - [GCP — Cloud Functions v2](#gcp--cloud-functions-v2)
    - [`gcp/serverless`](#gcpserverless)
  - [Azure — Azure Functions (Consumption)](#azure--azure-functions-consumption)
    - [`azure/serverless`](#azureserverless)
  - [Deploying](#deploying)
    - [Prerequisites](#prerequisites)
    - [Step 1 — Update IAM permissions](#step-1--update-iam-permissions)
    - [Step 2 — Commit and push](#step-2--commit-and-push)
    - [Step 3 — Deploy](#step-3--deploy)
    - [Step 4 — Smoke test](#step-4--smoke-test)
    - [Step 5 — Destroy](#step-5--destroy)
  - [Key differences across clouds](#key-differences-across-clouds)

## Introduction

Comparison of the serverless example across all three clouds. Each cloud gets a single **serverless** module that packages a small Python function as a zip archive, deploys it to the cloud's native Function-as-a-Service (FaaS) platform, and exposes it over HTTPS — no containers, no registries, no networking setup required.

The function adds two numbers passed as query parameters and returns the result as JSON:

```
GET {function-url}?a=3&b=5  →  {"result": 8.0}
```

### What each example provisions

|                      | AWS                         | GCP                          | Azure                               |
| -------------------- | --------------------------- | ---------------------------- | ----------------------------------- |
| **Module**           | `aws/serverless`            | `gcp/serverless`             | `azure/serverless`                  |
| **FaaS service**     | Lambda                      | Cloud Functions v2           | Azure Functions (Consumption)       |
| **Runtime**          | Python 3.12                 | Python 3.12                  | Python 3.11                         |
| **Packaging**        | zip via `archive_file`      | zip via `archive_file` → GCS | zip via `archive_file` → Blob       |
| **HTTP exposure**    | Lambda Function URL         | Built-in HTTP trigger        | Built-in HTTP trigger (`/api/add`)  |
| **Authentication**   | None (NONE auth type)       | None (`allUsers` IAM member) | None (`ANONYMOUS` auth level)       |
| **Scale to zero**    | Yes                         | Yes                          | Yes                                 |
| **Idle cost**        | £0                          | £0                           | £0                                  |
| **Region**           | `eu-west-2`                 | `europe-west1`               | `westeurope`                        |
| **IAM / role**       | Inline IAM role + 2 managed policies | GCS staging object + IAM member | Storage account + Service Plan |

## Concepts and terminology

### FaaS vs containers

The [containerised-app](containerised-app.md) example runs a long-lived container that stays warm between requests. FaaS takes the opposite approach: the function code is invoked on demand, and the platform manages all the underlying infrastructure. You upload your code; the cloud handles servers, operating systems, runtimes, and scaling.

The trade-off is that FaaS functions are stateless and short-lived (maximum execution time: 15 minutes on Lambda, 60 minutes on Cloud Functions, 10 minutes on Azure Functions). They are well suited to simple request-response workloads like this addition function, but not to long-running processes or workloads that require in-memory state between requests.

### Packaging and deployment

Unlike the containerised-app modules which require a container image to be built and pushed to a registry, the serverless modules deploy source code directly. Terraform's `archive_file` data source zips the Python file(s) locally during `terraform plan`. The zip is then:

- **AWS**: uploaded directly to Lambda via the `filename` argument — no intermediate storage needed
- **GCP**: uploaded to a GCS bucket (the existing state bucket is reused) as a versioned object, then referenced by the Cloud Functions build config
- **Azure**: uploaded to a Blob Storage container inside a dedicated storage account, then referenced by the Function App via `WEBSITE_RUN_FROM_PACKAGE`

The GCS and Azure blob object names include the zip's MD5 hash, so any change to the function source automatically triggers a re-upload and re-deployment.

### Cold starts

Because all three functions scale to zero, the first request after a period of inactivity incurs a **cold start** — the platform must initialise a new execution environment before handling the request. For this simple Python function, cold starts are typically under 1 second on Lambda and Cloud Functions. Azure Functions on the Consumption plan can take up to 30 seconds on a cold start.

The smoke test scripts use `--max-time 60` on Azure to accommodate this.

### Scaling and cost

All three functions scale to zero — there is no idle cost.

| Cloud              | Idle cost | Free tier (approx.)                          |
| ------------------ | --------- | -------------------------------------------- |
| AWS Lambda         | £0        | 1M requests/month + 400,000 GB-seconds/month |
| GCP Cloud Functions | £0       | 2M requests/month + 400,000 GB-seconds/month |
| Azure Functions    | £0        | 1M requests/month + 400,000 GB-seconds/month |

At the scale of this demo (a handful of test invocations), cost is effectively zero on all three clouds.

## The function

The function logic is the same across all three clouds. Only the handler signature differs to match each platform's invocation model.

| Cloud | File            | Entry point   | Handler signature                              |
| ----- | --------------- | ------------- | ---------------------------------------------- |
| AWS   | `function.py`   | `handler`     | `handler(event, context)`                      |
| GCP   | `function.py`   | `add`         | `add(request)` via `@functions_framework.http` |
| Azure | `function_app.py` | `add`       | `add(req: func.HttpRequest)` via `@app.route`  |

In all cases the function reads `a` and `b` from query parameters, converts them to floats, and returns `{"result": a + b}`. Invalid inputs return `{"error": "a and b must be numbers"}` with a 400 status.

## AWS — Lambda + Function URL

### `aws/serverless`

**Provisions:**
- `data.archive_file.function` — zips `function.py` locally at plan time
- `aws_iam_role.lambda` — execution role for the Lambda function; trusted by `lambda.amazonaws.com`
- `aws_iam_role_policy_attachment.basic_execution` — attaches `AWSLambdaBasicExecutionRole` (CloudWatch Logs write)
- `aws_iam_role_policy_attachment.xray` — attaches `AWSXRayDaemonWriteAccess` (X-Ray tracing)
- `aws_cloudwatch_log_group.lambda` — pre-creates the log group with 7-day retention so Terraform controls the lifecycle
- `aws_lambda_function.this` — Python 3.12 function with Active X-Ray tracing
- `aws_lambda_function_url.this` — HTTPS endpoint with `authorization_type = "NONE"` (publicly callable)

**Key design decisions:**
- **Lambda Function URL** is used instead of API Gateway. Function URLs are simpler (one resource vs five or more for an HTTP API Gateway) and sufficient for a single-function demo. They produce a stable HTTPS endpoint with no additional cost.
- **X-Ray tracing** is enabled (`mode = "Active"`) to satisfy the `AWS-0066` trivy check. For a demo function this adds no meaningful overhead.
- The log group is created explicitly before the function so that Terraform owns its lifecycle and can set retention. Without this, Lambda creates the log group automatically with no retention policy, and Terraform cannot import it cleanly.
- The IAM role name matches `var.function_name` (`tf-public-cloud-add`), and the apply IAM policy is scoped to `arn:aws:iam::*:role/tf-public-cloud-add` to follow least-privilege.

**Outputs:**

| Output          | Example value                                                          |
| --------------- | ---------------------------------------------------------------------- |
| `function_url`  | `https://abc123.lambda-url.eu-west-2.on.aws/`                          |
| `function_name` | `tf-public-cloud-add`                                                  |

**Test:**

```sh
./scripts/examples/serverless-aws.sh
```

## GCP — Cloud Functions v2

### `gcp/serverless`

**Provisions:**
- `data.archive_file.function` — zips `function.py` (packaged as `main.py`) and `requirements.txt` locally at plan time
- `google_storage_bucket_object.function` — uploads the zip to the state bucket under `serverless/`; the object name includes the MD5 hash so any source change forces a new upload
- `google_cloudfunctions2_function.this` — Cloud Functions v2 function; Python 3.12 runtime; entry point `add`; 128 MiB memory; max 1 instance
- `google_cloud_run_v2_service_iam_member.public` — grants `roles/run.invoker` to `allUsers` to make the function publicly callable

**Key design decisions:**
- **Cloud Functions v2** is built on Cloud Run under the hood — the function is compiled by Cloud Build into a container image and run as a Cloud Run service. The `google_cloud_run_v2_service_iam_member` resource (rather than `google_cloudfunctions2_function_iam_member`) is used to set the public IAM binding because that is what controls access to the underlying Cloud Run service.
- The function source file is packaged inside the zip as `main.py`. Cloud Functions expects `main.py` by default; the `GOOGLE_FUNCTION_SOURCE` build environment variable is also set explicitly to `main.py` to make the intent clear and avoid relying on the convention alone.
- The zip is staged in the **existing state bucket** (`tf-public-cloud-gcp-state-edo`) rather than creating a new bucket, keeping the module self-contained with no extra resources to manage.
- `source_bucket` is a variable (defaulting to the state bucket) so a dedicated bucket can be used if preferred.
- The `allUsers` IAM binding may fail if your GCP organisation enforces `constraints/iam.allowedPolicyMemberDomains`. In that case, remove the IAM member resource and invoke the function with a Bearer token: `curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" {url}?a=3&b=5`.

**Outputs:**

| Output          | Example value                                                     |
| --------------- | ----------------------------------------------------------------- |
| `function_url`  | `https://tf-public-cloud-add-abc123-ew.a.run.app`                 |
| `function_name` | `tf-public-cloud-add`                                             |

**Test:**

```sh
./scripts/examples/serverless-gcp.sh gcp-sandbox-2026-18798
```

## Azure — Azure Functions (Consumption)

### `azure/serverless`

**Provisions:**
- `random_id.suffix` — 2-byte random hex suffix for globally unique resource names
- `azurerm_resource_group.this` — resource group for all resources
- `azurerm_storage_account.this` — Standard LRS storage account required by the Azure Functions runtime; named `tfpubcloudfn{hex}` (14 characters, no hyphens)
- `azurerm_storage_container.deployments` — private blob container for the function zip
- `data.archive_file.function` — zips `function_app.py`, `requirements.txt`, and `host.json` locally at plan time
- `azurerm_storage_blob.function` — uploads the zip to the deployments container; name includes the MD5 hash
- `azurerm_service_plan.this` — Linux Consumption plan (`Y1` SKU); serverless billing with no idle cost
- `azurerm_linux_function_app.this` — Python 3.11 function app with `https_only = true` and `WEBSITE_RUN_FROM_PACKAGE` pointing to the uploaded blob

**Key design decisions:**
- **Azure Functions requires a Storage Account** for internal state (host coordination, timer triggers, deployment packages). This is a platform requirement, not a choice — every Function App on any plan needs one.
- `WEBSITE_RUN_FROM_PACKAGE` points to the blob URL. The Function App runtime downloads the zip at startup and runs the function directly from the read-only package — no extraction to the filesystem. This is the recommended deployment model for Consumption plan functions: it reduces startup time and avoids filesystem write contention.
- `https_only = true` enforces HTTPS — HTTP requests are redirected automatically.
- The Azure Functions v2 Python programming model is used (`function_app.py` with `@app.route` decorator). This is the current recommended model; it requires no `function.json` sidecar files.
- `host.json` is mandatory — the Functions runtime refuses to start without it.
- The default region is `westeurope`. `uksouth` was the original default but the subscription's Y1 Consumption plan VM quota is zero in that region.

**Outputs:**

| Output             | Example value                                                |
| ------------------ | ------------------------------------------------------------ |
| `function_url`     | `https://tfpubcloudfn3af1.azurewebsites.net/api/add`        |
| `function_app_name`| `tfpubcloudfn3af1`                                          |

**Test:**

```sh
./scripts/examples/serverless-azure.sh
```

> **Note:** The first invocation after a period of inactivity may take up to 30 seconds on the Consumption plan. The test script uses `--max-time 60` on all requests to accommodate this.

> **Note:** If your subscription has not previously used Azure Functions, the `Microsoft.Web` resource provider may not be registered. Run `az provider register --namespace Microsoft.Web --wait` and re-apply. Future bootstrap runs will register it automatically.

## Deploying

### Prerequisites

All existing GitHub Actions variables (`AWS_ROLE_ARN`, `AWS_REGION`, `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_SERVICE_ACCOUNT`, `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) must already be set from the bootstrap. No new variables are required.

The following APIs and provider namespaces must be enabled before the first apply:

| Cloud | Requirement                                                     | How to enable                                                                                              |
| ----- | --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| GCP   | `cloudfunctions.googleapis.com`, `cloudbuild.googleapis.com`    | Added to `bootstrap-gcp.sh` — re-run the bootstrap, or: `gcloud services enable cloudfunctions.googleapis.com cloudbuild.googleapis.com --project=PROJECT_ID` |
| Azure | `Microsoft.Web`                                                 | Added to `bootstrap-azure.sh` — re-run the bootstrap, or: `az provider register --namespace Microsoft.Web --wait` |

### Step 1 — Update IAM permissions

The new modules require additional permissions. Run the bootstrap apply scripts from the repo root — they are safe to re-run:

```sh
# AWS (Lambda + IAM role permissions)
./scripts/bootstrap/apply-aws-iam-policy.sh github-tf-public-cloud-plan  scripts/iam/aws-plan-policy.json
./scripts/bootstrap/apply-aws-iam-policy.sh github-tf-public-cloud-apply scripts/iam/aws-apply-policy.json

# GCP (roles/cloudfunctions.admin)
./scripts/bootstrap/apply-gcp-iam-bindings.sh \
  github-actions-tf@gcp-sandbox-2026-18798.iam.gserviceaccount.com \
  scripts/iam/gcp-permissions.json

# Azure — no new RBAC needed (Contributor already covers all resources)
```

### Step 2 — Commit and push

```sh
git add -A
git commit -m "Add serverless module: Python add function on Lambda, Cloud Functions v2, and Azure Functions"
git push
```

### Step 3 — Deploy

```sh
gh workflow run deploy-resource.yml \
  --field resource_type=serverless \
  --field cloud=all \
  --field action=apply
gh run watch
```

### Step 4 — Smoke test

Use the helper scripts in `scripts/examples/` — they look up the endpoint via the cloud CLI so no `terraform output` is needed:

```sh
./scripts/examples/serverless-aws.sh
./scripts/examples/serverless-gcp.sh gcp-sandbox-2026-18798
./scripts/examples/serverless-azure.sh
```

Expected output for each cloud:

```
==> Looking up {endpoint}
     https://...
==> GET ?a=3&b=5 (expect 8)
     Got expected result: 8.0
==> GET ?a=-1&b=1 (expect 0)
     Got expected result: 0.0
==> GET ?a=bad (expect 400)
     Got expected 400
==> Done
```

### Step 5 — Destroy

```sh
gh workflow run deploy-resource.yml \
  --field resource_type=serverless \
  --field cloud=all \
  --field action=destroy
gh run watch
```

## Key differences across clouds

| Aspect                    | AWS                                              | GCP                                              | Azure                                              |
| ------------------------- | ------------------------------------------------ | ------------------------------------------------ | -------------------------------------------------- |
| **HTTP exposure**         | Lambda Function URL (no API Gateway)             | Built-in Cloud Functions HTTPS trigger           | Built-in Functions HTTP trigger at `/api/{route}`  |
| **Code staging**          | Zip uploaded directly to Lambda                  | Zip uploaded to GCS, referenced by build config  | Zip uploaded to Blob Storage via `WEBSITE_RUN_FROM_PACKAGE` |
| **Build step**            | None — Lambda runs the zip directly              | Cloud Build compiles the function into a container image | None — runtime executes from the zip package |
| **Public access control** | `authorization_type = "NONE"` on Function URL    | `roles/run.invoker` granted to `allUsers`        | `http_auth_level = ANONYMOUS` on the route         |
| **Supporting resources**  | IAM role + CloudWatch log group                  | GCS object                                       | Storage account + storage container + service plan |
| **TLS**                   | HTTPS enforced (AWS-managed cert)                | HTTPS enforced (Google-managed cert)             | HTTPS enforced via `https_only = true`             |
| **Cold start**            | < 1s (Python, small package)                     | < 1s (Python, small package)                     | Up to 30s on first invocation (Consumption plan)   |
| **Python handler file**   | `function.py` (handler: `function.handler`)      | `function.py` (packaged as `main.py` in zip)     | `function_app.py` (Azure Functions v2 model)       |
| **Extra runtime files**   | None                                             | `requirements.txt`                               | `requirements.txt` + `host.json`                  |
| **Region**                | `eu-west-2`                                      | `europe-west1`                                   | `westeurope`                                       |
