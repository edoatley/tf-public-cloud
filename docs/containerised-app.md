# Containerised App

- [Containerised App](#containerised-app)
  - [Introduction](#introduction)
    - [Deployment flow](#deployment-flow)
    - [What each example provisions](#what-each-example-provisions)
  - [Concepts and terminology](#concepts-and-terminology)
    - [Container registries](#container-registries)
    - [Image naming conventions](#image-naming-conventions)
    - [Compute runtimes](#compute-runtimes)
    - [Networking and ingress](#networking-and-ingress)
    - [Health checks](#health-checks)
    - [Scaling and cost](#scaling-and-cost)
  - [The application](#the-application)
  - [AWS — ECR + ECS Fargate + ALB](#aws--ecr--ecs-fargate--alb)
    - [`aws/container-registry`](#awscontainer-registry)
    - [`aws/containerised-app`](#awscontainerised-app)
  - [GCP — Artifact Registry + Cloud Run](#gcp--artifact-registry--cloud-run)
    - [`gcp/container-registry`](#gcpcontainer-registry)
    - [`gcp/containerised-app`](#gcpcontainerised-app)
  - [Azure — ACR + Container Apps](#azure--acr--container-apps)
    - [`azure/container-registry`](#azurecontainer-registry)
    - [`azure/containerised-app`](#azurecontainerised-app)
  - [Deploying](#deploying)
    - [Prerequisites](#prerequisites)
    - [Step 1 — Update IAM permissions](#step-1--update-iam-permissions)
    - [Step 2 — Commit and push](#step-2--commit-and-push)
    - [Step 3 — Apply the container registries](#step-3--apply-the-container-registries)
    - [Step 4 — Build and push the image](#step-4--build-and-push-the-image)
    - [Step 5 — Deploy the app](#step-5--deploy-the-app)
    - [Step 6 — Smoke test](#step-6--smoke-test)
    - [Step 7 — Destroy](#step-7--destroy)
  - [Key differences across clouds](#key-differences-across-clouds)

## Introduction

Comparison of the containerised-app example across all three clouds. Each cloud gets a **container registry** module to store images, and a **containerised-app** module to run them. The two modules are kept separate to avoid the chicken-and-egg problem: the registry must exist before an image can be pushed, and an image must exist before the app module can deploy it.

### Deployment flow

```
container-registry apply  →  build-and-push  →  containerised-app apply
        (Terraform)              (Docker)              (Terraform)
```

The `containerised-app` module reads the registry URL directly from the `container-registry` remote state using `data "terraform_remote_state"` — no registry URL needs to be passed manually.

### What each example provisions

|                         | AWS                              | GCP                              | Azure                                    |
| ----------------------- | -------------------------------- | -------------------------------- | ---------------------------------------- |
| **Registry module**     | `aws/container-registry`         | `gcp/container-registry`         | `azure/container-registry`               |
| **Registry service**    | ECR (Elastic Container Registry) | Artifact Registry                | ACR (Azure Container Registry)           |
| **Registry name**       | `tf-public-cloud-app` (fixed)    | `tf-public-cloud-app` (fixed)    | `tfpubcloudacredoatley` (fixed, unique)  |
| **App module**          | `aws/containerised-app`          | `gcp/containerised-app`          | `azure/containerised-app`                |
| **Compute service**     | ECS Fargate                      | Cloud Run (v2)                   | Azure Container Apps                     |
| **Load balancing**      | Application Load Balancer (ALB)  | Built-in (Cloud Run URL)         | Built-in (Container Apps ingress)        |
| **vCPU / memory**       | 0.25 vCPU / 512 MiB              | 1 vCPU / 512 MiB                 | 0.25 vCPU / 0.5 GiB                      |
| **Scale to zero**       | No — desired_count = 1           | Yes — min_instances = 0          | Yes — min_replicas = 0                   |
| **Public access**       | Via ALB DNS name (HTTP)          | Via Cloud Run URL (HTTPS)        | Via Container Apps FQDN (HTTPS)          |
| **Registry auth in CI** | `aws ecr get-login-password`     | `gcloud auth configure-docker`   | `az acr login`                           |
| **App pulls image via** | IAM role on task execution role  | Implicit (same project, same SA) | ACR admin credentials stored as a secret |

## Concepts and terminology

### Container registries

Each cloud has a managed container registry that stores OCI-format Docker images. All three are private by default — only authenticated principals can push or pull.

**AWS ECR** is per-region and per-account. The repository URL has the form `{account-id}.dkr.ecr.{region}.amazonaws.com/{repository-name}`. Authentication uses a short-lived token retrieved with `aws ecr get-login-password`, which is piped into `docker login`. The token is valid for 12 hours. ECR is integrated with IAM — ECS tasks pull images using the task execution role, requiring no credentials stored anywhere.

**GCP Artifact Registry** replaces the older Container Registry service. Repositories are regional and scoped to a project. The URL has the form `{region}-docker.pkg.dev/{project}/{repository-id}`. Authentication uses `gcloud auth configure-docker` to register a credential helper, after which `docker push/pull` works transparently using the current gcloud identity. Cloud Run services can pull from Artifact Registry within the same project with no additional configuration.

**Azure ACR** is a resource within a resource group. The login server has the form `{registry-name}.azurecr.io`. The Basic SKU is the cheapest tier. This module enables admin credentials (`admin_enabled = true`) so that Container Apps can authenticate using a stored username and password — Container Apps does not currently support managed identity pull from ACR without a Premium SKU or additional configuration, making admin credentials the simplest approach for a Basic SKU registry.

### Image naming conventions

The image tag convention used across all three clouds is `{service-name}:{tag}`, where the service name is `tf-public-cloud-app` and the tag defaults to `latest`. The full image URIs are:

| Cloud | Full image URI                                                                        |
| ----- | ------------------------------------------------------------------------------------- |
| AWS   | `{account}.dkr.ecr.eu-west-2.amazonaws.com/tf-public-cloud-app:{tag}`                 |
| GCP   | `europe-west2-docker.pkg.dev/{project}/tf-public-cloud-app/tf-public-cloud-app:{tag}` |
| Azure | `tfpubcloudacredoatley.azurecr.io/tf-public-cloud-app:{tag}`                          |

Note that GCP Artifact Registry includes an extra path segment for the image name within the repository (the repository URL is a prefix, not the full image path). This differs from ECR and ACR where the repository URL is the image path directly.

### Compute runtimes

All three services run containers without requiring you to manage servers, but they differ significantly in their execution model.

**ECS Fargate** (AWS) is a serverless compute engine for containers defined via ECS task definitions. A task definition specifies the container image, CPU, memory, ports, health check, and log configuration. An ECS service runs one or more instances of the task and keeps them running. Fargate does not scale to zero — a running service always has at least one task consuming CPU and memory, which incurs a continuous cost (~£10–15/month for 0.25 vCPU / 512 MiB). An **Application Load Balancer** (ALB) is required to expose the service publicly, since Fargate tasks use `awsvpc` networking and do not have stable public IPs.

**Cloud Run** (GCP) runs stateless containers on demand. Each request triggers a container instance; when there are no requests, instances are scaled down to zero (no idle cost). The service is exposed via a stable HTTPS URL managed by Google. Cloud Run handles TLS termination, load balancing, and autoscaling automatically — no separate load balancer resource is needed. This makes the GCP module considerably simpler than the AWS equivalent.

**Azure Container Apps** is Azure's serverless container platform, similar in model to Cloud Run. Container Apps also supports scale-to-zero, so there is no idle cost. Ingress is handled by the Container Apps environment's built-in load balancer, and TLS termination is provided automatically for external ingress. A Container App Environment is a shared boundary for multiple apps — this module creates a dedicated environment per deployment.

### Networking and ingress

The networking story varies considerably across the three clouds.

**AWS** requires the most explicit networking setup. The `containerised-app` module provisions a dedicated VPC with two public subnets across two availability zones (required by ALB), an internet gateway, route tables, and two security groups — one for the ALB (port 80 inbound from anywhere) and one for ECS tasks (port 8080 inbound from the ALB security group only). Traffic flows: internet → ALB port 80 → target group → ECS task port 8080.

**GCP** requires no networking setup. Cloud Run services are deployed into Google's managed infrastructure and receive a public HTTPS URL automatically. The `google_cloud_run_v2_service_iam_member` resource with `member = "allUsers"` makes the service publicly accessible without authentication. Without this resource, access would require a Google identity token in the request header.

**Azure** requires a Container App Environment, which acts as a shared virtual network boundary for Container Apps. The environment itself has no additional networking resources in this module (using the managed, Consumption-based environment). Setting `external_enabled = true` on the ingress block makes the app reachable over the public internet via HTTPS. Azure manages the TLS certificate and DNS.

### Health checks

All three modules configure health checks against the Spring Boot Actuator endpoint `GET /actuator/health`, which returns `{"status":"UP"}` when the app is healthy.

| Cloud | Health check mechanism                                                               | Startup grace period                  |
| ----- | ------------------------------------------------------------------------------------ | ------------------------------------- |
| AWS   | ECS container health check (`wget` in the container) + ALB target group health check | 60 s `startPeriod` on container check |
| GCP   | Cloud Run liveness probe (HTTP GET)                                                  | 30 s `initial_delay_seconds`          |
| Azure | Container Apps liveness probe (HTTP GET)                                             | Default (no explicit delay)           |

AWS has two layers of health checking: the container-level check (which determines ECS task health) and the ALB target group check (which determines whether to route traffic). Both must pass before the service is considered healthy.

### Scaling and cost

| Cloud                | Idle cost     | Scale to zero | Notes                                                                             |
| -------------------- | ------------- | ------------- | --------------------------------------------------------------------------------- |
| AWS ECS Fargate      | ~£10–15/month | No            | `desired_count = 1` keeps one task running at all times                           |
| GCP Cloud Run        | £0            | Yes           | Billed per request and per 100ms of CPU/memory while handling requests            |
| Azure Container Apps | £0            | Yes           | `min_replicas = 0` enables scale-to-zero; Consumption plan billed per vCPU-second |

Because this example is intended for testing and then destroying, the ongoing cost is only relevant if you leave the resources running. Destroy everything when done (see [Step 7](#step-7--destroy)).

## The application

The app lives in `app/` and is a Spring Boot 3.4 REST API built with Gradle 8 and Java 21. It exposes:

| Endpoint               | Description                                                                  |
| ---------------------- | ---------------------------------------------------------------------------- |
| `GET /api/items`       | Returns a JSON array of all items                                            |
| `GET /api/items/{id}`  | Returns a single item by ID, or 404 if not found                             |
| `GET /actuator/health` | Spring Boot Actuator health endpoint (used by all three cloud health checks) |

The app uses an in-memory item list — there is no database. It is packaged as a self-contained fat JAR by `gradle bootJar` and then built into a container image using a multi-stage Dockerfile:

- **Build stage**: `gradle:8-jdk21` — runs `gradle bootJar` inside the container, keeping the build environment reproducible and independent of the local Java version
- **Runtime stage**: `eclipse-temurin:21-jre-alpine` — slim JRE-only image (~80 MB smaller than a full JDK image); the app runs as a non-root user

## AWS — ECR + ECS Fargate + ALB

### `aws/container-registry`

**Provisions:**
- `aws_ecr_repository` — private ECR repository named `tf-public-cloud-app`
- `aws_ecr_lifecycle_policy` — keeps the 10 most recent images; older images are expired automatically

**Key design decisions:**
- `image_tag_mutability = "MUTABLE"` allows the `latest` tag to be overwritten on each push, which is convenient for a demo
- `scan_on_push = true` enables ECR Basic Scanning (free) to detect known CVEs in pushed images
- `encryption_type = "AES256"` uses SSE-S3 managed encryption — sufficient for a demo without the cost and complexity of a KMS key

**Outputs consumed by `containerised-app`:**

| Output            | Example value                                                   |
| ----------------- | --------------------------------------------------------------- |
| `repository_url`  | `123456789.dkr.ecr.eu-west-2.amazonaws.com/tf-public-cloud-app` |
| `repository_name` | `tf-public-cloud-app`                                           |

### `aws/containerised-app`

**Provisions:**
- VPC (`10.1.0.0/16`) with two public subnets across AZs `a` and `b`
- Internet gateway + route table
- Security group for ALB (port 80 inbound) and security group for ECS tasks (port 8080 from ALB only)
- IAM execution role with `AmazonECSTaskExecutionRolePolicy` (allows ECR pull and CloudWatch Logs write)
- ECS cluster with FARGATE capacity provider
- CloudWatch log group (`/ecs/tf-public-cloud-app`, 7-day retention)
- ECS task definition (0.25 vCPU / 512 MiB, health check via `wget` against `/actuator/health`)
- ECS service (desired count 1, FARGATE launch type)
- ALB + target group (target type `ip`) + HTTP listener on port 80

**Key design decisions:**
- Two subnets across two AZs are required — ALB will not provision into a single AZ
- The ECS task security group restricts port 8080 to traffic from the ALB security group only; the app is not directly reachable from the internet
- The task execution role uses the AWS-managed `AmazonECSTaskExecutionRolePolicy` rather than a custom inline policy, since it already grants exactly the ECR pull and log write permissions needed
- `tostring(var.cpu)` and `tostring(var.memory)` are required because `aws_ecs_task_definition` expects string values for CPU and memory in Fargate mode, even though the variables are declared as numbers for easier input

**Outputs:**

| Output         | Example value                                                |
| -------------- | ------------------------------------------------------------ |
| `alb_dns_name` | `tf-public-cloud-app-alb-123456.eu-west-2.elb.amazonaws.com` |
| `service_name` | `tf-public-cloud-app`                                        |
| `cluster_name` | `tf-public-cloud-app`                                        |

## GCP — Artifact Registry + Cloud Run

### `gcp/container-registry`

**Provisions:**
- `google_artifact_registry_repository` — Docker-format repository in `europe-west2`
- `google_artifact_registry_repository_iam_member` — grants `roles/artifactregistry.writer` to the CI service account

The IAM binding is managed in Terraform rather than via the `gcp-permissions.json` bootstrap because it is scoped to the specific repository (not the project), and it requires the repository to exist first.

**Key design decisions:**
- `ci_service_account` is a required variable — it is passed automatically via `TF_VAR_ci_service_account` in the deploy workflow, set from the `GCP_SERVICE_ACCOUNT` repo variable
- The `repository_url` output is computed locally (`"${var.region}-docker.pkg.dev/${var.project}/${var.repository_id}"`) rather than from a resource attribute, since Artifact Registry URLs follow a deterministic pattern

**Outputs consumed by `containerised-app`:**

| Output           | Example value                                                |
| ---------------- | ------------------------------------------------------------ |
| `repository_url` | `europe-west2-docker.pkg.dev/my-project/tf-public-cloud-app` |

### `gcp/containerised-app`

**Provisions:**
- `google_cloud_run_v2_service` — Cloud Run service in `europe-west1` (note: different region from the registry in `europe-west2` — Cloud Run is not available in `europe-west2`)
- `google_cloud_run_v2_service_iam_member` — grants `roles/run.invoker` to `allUsers` (public access)

**Key design decisions:**
- `min_instance_count = 0` enables scale-to-zero — the service incurs no cost when idle
- The image URI appends the image name as a sub-path within the repository: `{repository_url}/tf-public-cloud-app:{tag}`. This differs from ECR and ACR where the repository URL is the image path directly
- The `allUsers` IAM binding makes the service publicly accessible. If your GCP organisation has a policy restricting `allUsers` bindings (`constraints/iam.allowedPolicyMemberDomains`), this binding will fail — in that case, remove it and test with an authenticated `gcloud` token
- Cloud Run in `europe-west1` pulling images from Artifact Registry in `europe-west2` is cross-region but within the same Google network — no additional configuration is needed and egress costs are minimal

**Outputs:**

| Output         | Example value                                     |
| -------------- | ------------------------------------------------- |
| `service_url`  | `https://tf-public-cloud-app-abc123-ew.a.run.app` |
| `service_name` | `tf-public-cloud-app`                             |

## Azure — ACR + Container Apps

### `azure/container-registry`

**Provisions:**
- `azurerm_resource_group` — resource group for the registry
- `azurerm_container_registry` — ACR with Basic SKU, named `tfpubcloudacredoatley`

The registry name is fixed (no random suffix) so the `build-and-push` workflow and the `containerised-app` module can reference it by a known value without querying state or requiring a variable to be set after apply.

**Key design decisions:**
- `admin_enabled = true` is required — Container Apps with a Basic SKU ACR authenticates using the admin username and password, which the `containerised-app` module reads from the registry's remote state outputs and stores as a Container Apps secret
- The registry name `tfpubcloudacredoatley` is alphanumeric only (no hyphens — ACR names do not allow them) and globally unique by incorporating the owner's name
- No `random` provider is needed since the name is fully fixed

**Outputs consumed by `containerised-app`:**

| Output           | Sensitive | Example value                      |
| ---------------- | --------- | ---------------------------------- |
| `login_server`   | No        | `tfpubcloudacredoatley.azurecr.io` |
| `admin_username` | No        | `tfpubcloudacredoatley`            |
| `admin_password` | Yes       | `(redacted)`                       |
| `registry_name`  | No        | `tfpubcloudacredoatley`            |

### `azure/containerised-app`

**Provisions:**
- `azurerm_resource_group` — dedicated resource group for the app
- `azurerm_container_app_environment` — shared environment (Consumption plan)
- `azurerm_container_app` — the container app with external ingress on port 8080

**Key design decisions:**
- The ACR admin password is stored as a Container Apps `secret` and referenced by name in the `registry` block — it is never stored in plaintext in state beyond the remote state of the registry module
- `min_replicas = 0` enables scale-to-zero; the app costs nothing when not receiving traffic
- `revision_mode = "Single"` means each deploy creates a new revision and immediately routes 100% of traffic to it, which is appropriate for a demo
- The `data "terraform_remote_state"` block uses `use_azuread_auth = true` to match the backend configuration of the registry module — the same OIDC credentials that authenticate the provider also access the state blob

**Outputs:**

| Output     | Example value                                                |
| ---------- | ------------------------------------------------------------ |
| `app_fqdn` | `tf-public-cloud-app.{random}.uksouth.azurecontainerapps.io` |
| `app_name` | `tf-public-cloud-app`                                        |

> **Note:** If your subscription has not previously used Container Apps, the `Microsoft.App` resource provider may not be registered. If the apply fails with a provider registration error, run `az provider register --namespace Microsoft.App` and re-apply.

## Deploying

### Prerequisites

All existing GitHub Actions variables (`AWS_ROLE_ARN`, `AWS_REGION`, `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_SERVICE_ACCOUNT`, `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) must already be set from the bootstrap. No new variables are required.

### Step 1 — Update IAM permissions

The new modules require additional permissions for ECR, ECS, ELB, CloudWatch Logs (AWS), Artifact Registry, Cloud Run (GCP), and AcrPush (Azure). Run the bootstrap scripts from the repo root — they read the updated JSON files and are safe to re-run:

```sh
# AWS
./scripts/bootstrap/apply-aws-iam-policy.sh github-tf-public-cloud-plan  scripts/iam/aws-plan-policy.json
./scripts/bootstrap/apply-aws-iam-policy.sh github-tf-public-cloud-apply scripts/iam/aws-apply-policy.json

# GCP
./scripts/bootstrap/apply-gcp-iam-bindings.sh \
  github-actions-tf@gcp-sandbox-2026-18798.iam.gserviceaccount.com \
  scripts/iam/gcp-permissions.json

# Azure
./scripts/bootstrap/apply-azure-rbac.sh 709d0fbb-cd53-4a53-9d53-2db74a0151d7 scripts/iam/azure-permissions.json
```

### Step 2 — Commit and push

```sh
git add -A
git commit -m "Add containerised app: Spring Boot API, container registries, and Fargate/Cloud Run/Container Apps modules"
git push
```

### Step 3 — Apply the container registries

```sh
gh workflow run deploy-resource.yml \
  --field resource_type=container-registry \
  --field cloud=all \
  --field action=apply
gh run watch
```

### Step 4 — Build and push the image

```sh
gh workflow run build-and-push.yml \
  --field cloud=all \
  --field image_tag=latest
gh run watch
```

### Step 5 — Deploy the app

```sh
gh workflow run deploy-resource.yml \
  --field resource_type=containerised-app \
  --field cloud=all \
  --field action=apply
gh run watch
```

### Step 6 — Smoke test

Use the helper scripts in `scripts/examples/` — they look up the endpoint via the cloud CLI so no `terraform output` is needed:

```sh
./scripts/examples/containerised-app-aws.sh
./scripts/examples/containerised-app-gcp.sh
./scripts/examples/containerised-app-azure.sh
```

GCP and Azure may take 30–60 seconds to respond on the very first request (cold start from zero replicas).

#### AWS

<details>
<summary>Example AWS output</summary>

```terminaloutput
==> Looking up ALB DNS name
     http://tf-public-cloud-app-alb-2131323580.eu-west-2.elb.amazonaws.com
==> GET /api/items
[
  {
    "id": 1,
    "name": "Widget",
    "description": "A small reusable component"
  },
  {
    "id": 2,
    "name": "Gadget",
    "description": "A handy electronic device"
  },
  {
    "id": 3,
    "name": "Doohickey",
    "description": "A thing whose name you can't recall"
  }
]
==> GET /api/items/1
{
  "id": 1,
  "name": "Widget",
  "description": "A small reusable component"
}
==> GET /api/items/99 (expect 404)
     Got expected 404
==> GET /actuator/health
{
  "status": "UP"
}
==> Done
```

</details>

#### GCP

<details>
<summary>Example GCP output</summary>

```terminaloutput
==> Looking up Cloud Run service URL
     https://tf-public-cloud-app-lkatnppnna-ew.a.run.app
==> GET /api/items
[
  {
    "id": 1,
    "name": "Widget",
    "description": "A small reusable component"
  },
  {
    "id": 2,
    "name": "Gadget",
    "description": "A handy electronic device"
  },
  {
    "id": 3,
    "name": "Doohickey",
    "description": "A thing whose name you can't recall"
  }
]
==> GET /api/items/1
{
  "id": 1,
  "name": "Widget",
  "description": "A small reusable component"
}
==> GET /api/items/99 (expect 404)
     Got expected 404
==> GET /actuator/health
{
  "status": "UP"
}
==> Done
```

</details>

#### Azure

<details>
<summary>Example Azure output</summary>

```terminaloutput
==> Looking up Container App FQDN
     https://tf-public-cloud-app--mnvr7ft.orangebeach-4b43b5bf.uksouth.azurecontainerapps.io
==> GET /api/items
[
  {
    "id": 1,
    "name": "Widget",
    "description": "A small reusable component"
  },
  {
    "id": 2,
    "name": "Gadget",
    "description": "A handy electronic device"
  },
  {
    "id": 3,
    "name": "Doohickey",
    "description": "A thing whose name you can't recall"
  }
]
==> GET /api/items/1
{
  "id": 1,
  "name": "Widget",
  "description": "A small reusable component"
}
==> GET /api/items/99 (expect 404)
     Got expected 404
==> GET /actuator/health
{
  "status": "UP",
  "groups": [
    "liveness",
    "readiness"
  ]
}
==> Done
```

</details>

### Step 7 — Destroy

Destroy in reverse order — app first, then registry. Destroying the registry while the app still references its images would leave the app in a broken state.

```sh
# Destroy the app
gh workflow run deploy-resource.yml \
  --field resource_type=containerised-app \
  --field cloud=all \
  --field action=destroy
gh run watch

# Destroy the registry
gh workflow run deploy-resource.yml \
  --field resource_type=container-registry \
  --field cloud=all \
  --field action=destroy
gh run watch
```

## Key differences across clouds

| Aspect                  | AWS                                                          | GCP                                                  | Azure                                                  |
| ----------------------- | ------------------------------------------------------------ | ---------------------------------------------------- | ------------------------------------------------------ |
| **Registry auth model** | Short-lived token via `aws ecr get-login-password` (12h TTL) | Credential helper via `gcloud auth configure-docker` | `az acr login` using OIDC identity                     |
| **App pulls image via** | IAM task execution role (no credentials stored)              | Implicit — same project, same service account        | Admin username/password stored as Container App secret |
| **Load balancer**       | Explicit ALB required (separate resource)                    | Built into Cloud Run (no extra resource)             | Built into Container Apps environment                  |
| **TLS**                 | HTTP only (no TLS on ALB in this module)                     | HTTPS enforced (Google-managed cert)                 | HTTPS enforced (Azure-managed cert)                    |
| **Networking setup**    | VPC + 2 subnets + IGW + route tables + 2 SGs                 | None required                                        | Container App Environment only                         |
| **Scale to zero**       | No — continuous cost at idle                                 | Yes                                                  | Yes                                                    |
| **Image URI structure** | `{registry}/{repo-name}:{tag}`                               | `{registry}/{repo-name}/{image-name}:{tag}`          | `{registry}/{image-name}:{tag}`                        |
| **Region split**        | Registry and app both in `eu-west-2`                         | Registry `europe-west2`, app `europe-west1`*         | Registry and app both in `uksouth`                     |
| **Destroy order**       | `containerised-app` → `container-registry`                   | `containerised-app` → `container-registry`           | `containerised-app` → `container-registry`             |

\* Cloud Run is not available in `europe-west2`; `europe-west1` is the nearest supported region. Cross-region image pulls within GCP work without additional configuration.
