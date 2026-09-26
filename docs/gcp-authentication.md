# GCP Authentication: GitHub Actions to Google Cloud

How a GitHub Actions job ends up holding credentials for a GCP service account, with no key
file anywhere. This is the GCP-specific companion to the cross-cloud overview in
[docs/blog/Multi-Cloud-1-Zero-Trust.md](blog/Multi-Cloud-1-Zero-Trust.md) — read that first for
the OIDC concept and the AWS and Azure equivalents.

## Table of Contents

- [The short version](#the-short-version)
- [Phase 1: Bootstrap (one-time, from a laptop)](#phase-1-bootstrap-one-time-from-a-laptop)
- [Phase 2: Per-job authentication (every workflow run)](#phase-2-per-job-authentication-every-workflow-run)
- [Why the two gates are independent](#why-the-two-gates-are-independent)
- [Where each value lives](#where-each-value-lives)
- [Troubleshooting](#troubleshooting)

## The short version

GCP does not trust GitHub directly. It trusts a **Workload Identity Federation (WIF) provider**
that has been told GitHub's OIDC issuer URL, and that provider maps GitHub's JWT claims onto
Google attributes. Those attributes are what IAM bindings are written against.

Unlike AWS — where one `AssumeRoleWithWebIdentity` call returns usable credentials — GCP takes
**two** legs:

1. `sts.googleapis.com` exchanges the GitHub JWT for a *federated* token whose identity is a
   `principalSet`, not a service account.
2. `iamcredentials.googleapis.com` uses that federated token to **impersonate** a service
   account, which is where `roles/iam.workloadIdentityUser` is checked.

Both legs are performed lazily, inside Terraform and `gcloud`, not by the login action. That
detail matters when debugging: a green "Authenticate to GCP" step does not prove the exchange
works, only that the credential *configuration* was written.

## Phase 1: Bootstrap (one-time, from a laptop)

All of this is `scripts/bootstrap/bootstrap-gcp.sh`, which is idempotent — re-run it freely.

### 1. Enable the APIs

`sts` and `iamcredentials` are the two endpoints the exchange itself calls. Without them the
token exchange fails even though every IAM binding is correct. The rest (`storage`, `iam`,
`cloudresourcemanager`, `compute`, `cloudfunctions`, `cloudbuild`) are for the example modules.

### 2. Create the state bucket

`gs://tf-public-cloud-gcp-state-edo` with uniform bucket-level access, versioning, and public
access prevention. Terraform's `backend "gcs"` authenticates with the same credentials as the
provider, so state access and resource access are granted to the same identity.

### 3. Create the WIF pool and OIDC provider

A pool (`github-pool`, `--location=global`) holds providers. The provider (`github-provider`)
carries the trust configuration:

```sh
--issuer-uri="https://token.actions.githubusercontent.com"
--attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref,attribute.environment=assertion.environment"
--attribute-condition="assertion.repository == \"edoatley/tf-public-cloud\""
```

Three things to note:

- **`attribute.environment` is not mapped by default.** Without that mapping the apply binding
  in step 5 can never match, and every apply fails with a permission error that looks like a
  missing role.
- **The attribute condition is the first gate.** A token from any other repository is rejected
  at the provider, before any service account binding is even consulted.
- **The issuer URI is how the signature is verified.** GCP fetches GitHub's public JWKS from
  that issuer — there is no shared secret to rotate.

### 4. Create two service accounts

| Service account | Purpose |
| --------------- | ------- |
| `github-actions-tf-plan` | Read-only. Used by validate and plan. |
| `github-actions-tf-apply` | Write. Used by apply, destroy, and image push. |

### 5. Decide who may impersonate each one

This is the security boundary, and it is a binding **on the service account itself**, granting
`roles/iam.workloadIdentityUser` to a `principalSet` derived from the mapped attributes:

```text
# plan SA — any token from this repository: any branch, any PR, any dispatch
principalSet://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool/attribute.repository/edoatley/tf-public-cloud

# apply SA — only tokens carrying environment:production
principalSet://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool/attribute.environment/production
```

The plan trust scope is deliberately broad. Breadth is harmless when the identity carries no
write permissions, and it lets plan run on feature branches and PRs without ceremony.

### 6. Decide what each one may do

`scripts/bootstrap/apply-gcp-iam-bindings.sh` reads the role lists from JSON so permissions
review as a diff:

| File | Grants |
| ---- | ------ |
| `scripts/iam/gcp-plan-permissions.json` | `roles/viewer` on the project, plus `storage.objectAdmin` and `storage.legacyBucketReader` on the state bucket |
| `scripts/iam/gcp-apply-permissions.json` | The same state-bucket access, plus `storage.admin`, `compute.admin`, `run.admin`, `artifactregistry.admin`, `cloudfunctions.admin`, `monitoring.admin`, `iam.serviceAccountUser` |

`storage.legacyBucketReader` is there for a non-obvious reason: `terraform init` calls
`storage.buckets.get`, which `objectAdmin` does not include.

### 7. Write the GitHub side

The script sets `GCP_SERVICE_ACCOUNT` as an **environment-level** variable via `gh api`:

| GitHub environment | Value |
| ------------------ | ----- |
| `default` | `github-actions-tf-plan@<project>.iam.gserviceaccount.com` |
| `production` | `github-actions-tf-apply@<project>.iam.gserviceaccount.com` |

`GCP_WIF_PROVIDER` and `GCP_PROJECT_ID` are printed for you to set as repo-level variables.

> [!IMPORTANT]
> There is deliberately **no repo-level `GCP_SERVICE_ACCOUNT`**. If a job forgets to declare an
> environment, `vars.GCP_SERVICE_ACCOUNT` resolves to empty and the job fails loudly, rather
> than silently falling back to the plan identity. See
> [docs/GitHub.md](GitHub.md#why-gcp_service_account-is-environment-scoped).

## Phase 2: Per-job authentication (every workflow run)

### Step 1 — the workflow requests the right to have a token

```yaml
permissions:
  contents: read
  id-token: write
```

Declared at the top of `plan-resource.yml`, `apply-resource.yml`, `build-and-push.yml`, and
`terraform.yml`. Without `id-token: write` GitHub will not mint a JWT at all.

### Step 2 — the job declares an environment

```yaml
environment: default      # plan jobs
environment: production   # apply, destroy, and image-push jobs
```

One declaration, two effects. It selects which `GCP_SERVICE_ACCOUNT` value `vars.` resolves to,
**and** it causes GitHub to include `"environment": "production"` in the JWT. Because a single
line drives both halves, the credential a job asks for and the claim it can prove cannot drift
apart.

### Step 3 — GitHub environment protection runs

For `production`: reviewer approval, and the `release-*` ref restriction. This happens entirely
inside GitHub, before any token is minted.

### Step 4 — the login action runs

`terraform-setup` delegates to `cloud-login`, which for GCP is:

```yaml
- name: Authenticate to GCP
  if: inputs.cloud == 'gcp'
  uses: google-github-actions/auth@v3
  with:
    workload_identity_provider: ${{ inputs.gcp_wif_provider }}
    service_account: ${{ inputs.gcp_service_account }}
```

The action requests an OIDC JWT from the runner's token endpoint, using the WIF provider
resource name as the audience.

### Step 5 — it writes a credential config, not a token

No `token_format` is set, so the action takes its default path: it writes the JWT to a file,
and writes a credential configuration JSON that points at that file and carries the service
account's impersonation URL. It exports `GOOGLE_APPLICATION_CREDENTIALS` at that config.

Nothing has been exchanged yet. The step passes as long as the files could be written.

### Step 6 — leg one: STS

The first Google client to need credentials — Terraform, or `gcloud` — reads the config and
POSTs the JWT to `sts.googleapis.com`. Google verifies GitHub's signature against the issuer,
applies the provider's attribute condition, and maps claims to attributes. What comes back is a
federated token whose identity *is* the `principalSet`.

### Step 7 — leg two: impersonation

That federated identity calls `generateAccessToken` on `iamcredentials.googleapis.com` for the
target service account. **This is where `roles/iam.workloadIdentityUser` is checked.** A
`default`-environment job that somehow asked for the apply SA fails right here. On success: a
service account access token, valid roughly an hour, never written to persistent storage.

### Step 8 — Terraform uses it

`backend "gcs"` and `provider "google"` both resolve credentials through Application Default
Credentials, which finds `GOOGLE_APPLICATION_CREDENTIALS`. The project is passed separately, as
a Terraform variable rather than through the credentials:

```yaml
extra_vars: -var="project=${{ vars.GCP_PROJECT_ID }}"
```

which lands in `provider "google" { project = var.project }`.

### Step 9 — Docker pushes use the same credentials

In `build-and-push.yml`, `gcloud auth configure-docker europe-west2-docker.pkg.dev` installs a
credential helper that resolves through the same ADC, so `docker push` needs no separate login.

Note the loop this closes: `gcp/container-registry/main.tf` grants
`roles/artifactregistry.writer` on the new repository to `var.ci_service_account`, fed in as
`TF_VAR_ci_service_account: ${{ vars.GCP_SERVICE_ACCOUNT }}`. Terraform grants push rights to
the identity that ran it.

## Why the two gates are independent

GitHub environment protection and the GCP `principalSet` condition are separate systems, and
both must pass:

- Skip the GitHub gate, and the job has no `environment: production` claim — leg two fails at
  GCP.
- Try to forge the claim, and the JWT signature no longer verifies — GitHub signs it.
- Compromise a GCP role binding, and you still cannot get a token without a GitHub workflow run
  in the `production` environment.

## Where each value lives

| Value | Where it is set | Read by |
| ----- | --------------- | ------- |
| `GCP_WIF_PROVIDER` | Repo variable (manual, value printed by bootstrap) | `cloud-login`, as the audience and exchange target |
| `GCP_PROJECT_ID` | Repo variable (manual) | Passed to Terraform as `-var="project=..."` |
| `GCP_SERVICE_ACCOUNT` | Environment variable, set automatically by bootstrap | `cloud-login`, as the impersonation target; also `TF_VAR_ci_service_account` |
| WIF pool, provider, attribute mapping | `bootstrap-gcp.sh` | GCP, at exchange time |
| `workloadIdentityUser` bindings | `bootstrap-gcp.sh` | GCP, at impersonation time |
| Project and bucket roles | `scripts/iam/gcp-*-permissions.json` | GCP, on every API call Terraform makes |

## Troubleshooting

| Symptom | Likely cause |
| ------- | ------------ |
| `Unable to acquire impersonated credentials` on an apply job | The job is missing `environment: production`, so the JWT carries no `environment` claim and the apply SA's `principalSet` does not match |
| The same error on every job, including plan | `attribute.environment` or `attribute.repository` missing from the provider's attribute mapping — re-run `bootstrap-gcp.sh`, which updates the mapping in place |
| `The caller does not have permission` on `terraform init` only | Missing `roles/storage.legacyBucketReader` on the state bucket (`storage.buckets.get`) |
| Auth step passes, first Terraform call fails | Expected shape of failure — the exchange happens inside Terraform, not in the auth step. Read the Terraform error, not the auth step |
| `Permission 'iam.serviceAccounts.getAccessToken' denied` | The `workloadIdentityUser` binding is on the wrong service account, or the pool project number in the `principalSet` is wrong |
| Empty service account in the auth step | The job declared no environment, and there is no repo-level `GCP_SERVICE_ACCOUNT` by design |

To prove the whole chain end to end without creating anything, run the smoke test — it resolves
`google_project` and `google_client_openid_userinfo`, so it reports back the project and the
service account email actually in use:

```sh
gh workflow run plan-resource.yml \
  --field resource_type=smoke-test \
  --field cloud=gcp \
  --field action=plan
gh run watch
```
