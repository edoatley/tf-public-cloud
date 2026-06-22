# Containerised App (ECS Fargate) — Deployment Guide

This guide covers deploying the `aws/containerised-app-prod` Terraform module and validating it end-to-end with a TLS hostname (`fargate-test.edoatley.co.uk`).

---

## Architecture overview

```
Internet
  │
  ▼
Route53  fargate-test.edoatley.co.uk  (A alias → ALB)
  │
  ▼
ALB  (public, HTTPS:443 / HTTP:80→redirect)   ← ACM certificate
  │
  ▼ (port 8080, security group locked to ALB)
ECS Fargate tasks  (private subnets, 2 AZs)
  │
  ▼ (outbound via NAT gateway)
ECR (Docker image pull) + CloudWatch Logs
```

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| `aws` CLI | Look up resources, trigger deploys, tail logs |
| `terraform` ≥ 1.6 | Local plan/validate |
| `gh` | Trigger GitHub Actions workflows |
| `jq` | Parse JSON in scripts |
| `curl` | Call the API |
| `docker` | Local image build (CI only, not needed manually) |

AWS CLI profiles needed:
- `sandbox` — account 793976186123 (where the infrastructure lives)
- A prod-account profile with Route53 write access to `edoatley.co.uk` (for the NS delegation step only)

---

## Step 1 — One-time DNS bootstrap

`edoatley.co.uk` is owned by account 705251932900. The subdomain `fargate-test.edoatley.co.uk` needs to be delegated to a hosted zone in the sandbox account (793976186123). This is a one-time manual step.

### 1a. Create the hosted zone in sandbox

Since the zone already exists, retrieve its ID and NS records:

```bash
# Get the zone ID
ZONE_ID=$(aws route53 list-hosted-zones \
  --profile sandbox \
  --query "HostedZones[?Name=='fargate-test.edoatley.co.uk.'].Id" \
  --output text | sed 's|/hostedzone/||')
echo "Zone ID: ${ZONE_ID}"

# Z08071841XW6QGVOS5UD9

# Get the NS records for delegation
aws route53 list-resource-record-sets \
  --hosted-zone-id "${ZONE_ID}" \
  --profile sandbox \
  --query "ResourceRecordSets[?Type=='NS'].ResourceRecords[*].Value" \
  --output text

# ns-1355.awsdns-41.org.  ns-6.awsdns-00.com.     ns-595.awsdns-10.net.   ns-1911.awsdns-46.co.uk.
```

<details>
<Summary>If you still need to create the zone (first time only):</summary>

```bash
ZONE_ID=$(aws route53 create-hosted-zone \
  --name fargate-test.edoatley.co.uk \
  --caller-reference "fargate-test-$(date +%s)" \
  --profile sandbox \
  --query 'HostedZone.Id' \
  --output text | sed 's|/hostedzone/||')
echo "Zone ID: ${ZONE_ID}"

aws route53 list-resource-record-sets \
  --hosted-zone-id "${ZONE_ID}" \
  --profile sandbox \
  --query "ResourceRecordSets[?Type=='NS'].ResourceRecords[*].Value" \
  --output text
```

Note the zone ID and the four NS values — you need both for the next two steps.

</details>

### 1b. Delegate from the parent zone

In the **prod account** (705251932900, profile name `backups`), add an NS record to the `edoatley.co.uk` hosted zone:

```bash
# Find the parent zone ID (prod account profile)
PARENT_ZONE=$(aws route53 list-hosted-zones \
  --profile backups \
  --query "HostedZones[?Name=='edoatley.co.uk.'].Id" \
  --output text | sed 's|/hostedzone/||')

# Z055000739D7L0ZGFAMC1

# Create the NS delegation record
aws route53 change-resource-record-sets \
  --hosted-zone-id "${PARENT_ZONE}" \
  --profile backups \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "fargate-test.edoatley.co.uk",
        "Type": "NS",
        "TTL": 300,
        "ResourceRecords": [
          {"Value": "ns-1355.awsdns-41.org."},
          {"Value": "ns-6.awsdns-00.com."},
          {"Value": "ns-595.awsdns-10.net."},
          {"Value": "ns-1911.awsdns-46.co.uk."}
        ]
      }
    }]
  }'
```       

> [!IMPORTANT]
> Replace the four NS values with the actual values from step 1a.

```output
{
    "ChangeInfo": {
        "Id": "/change/C0174805KCMPMBLY3QUA",
        "Status": "PENDING",
        "SubmittedAt": "2026-06-21T12:42:21.384000+00:00"
    }
}
```

---

## Step 2 — Apply the container registry

If the ECR repository does not already exist, create a `release-*` tag and dispatch against it (the `production` environment only permits `release-*` refs):

```bash
git tag release-1.0.0
git push origin release-1.0.0
gh workflow run apply-resource.yml \
  --field resource_type=container-registry \
  --field cloud=aws \
  --field action=apply \
  --ref release-1.0.0
gh run watch
```

---

## Step 3 — Apply the containerised-app-prod infrastructure

```bash
gh workflow run apply-resource.yml \
  --field resource_type=containerised-app-prod \
  --field cloud=aws \
  --field action=apply \
  --ref release-1.0.0
gh run watch
```

This creates: VPC + subnets, NAT gateway, ALB, ACM certificate (DNS-validated via Route53), ECS cluster/service/task definition, auto-scaling, CloudWatch alarms and dashboard.

The apply takes approximately 5–8 minutes. ACM DNS validation adds ~2 minutes once the CNAME is in place.

After apply, confirm the A record is present:

```bash
dig fargate-test.edoatley.co.uk A +short
# Should return the ALB IPs within a minute or two of DNS propagation
```

---

## Step 4 — Build and deploy the app

The GitHub `production` environment only permits deployments from refs matching `release-*`. Create a tag from the `fargate` branch and push it, then dispatch the workflow against that tag:

```bash
git tag release-1.0.0
git push origin release-1.0.0
gh workflow run deploy-app.yml --ref release-1.0.0
gh run watch
```

This:
1. Authenticates to ECR
2. Builds the Spring Boot Docker image from `app/`
3. Pushes with the commit SHA tag and `latest` tag
4. Forces a rolling ECS deployment (`update-service --force-new-deployment`)
5. Waits for service stability (all tasks healthy)

Takes ~5 minutes for build + ECS rollout.

---

## Step 5 — Verify the deployment

```bash
# Health check
curl -sf https://fargate-test.edoatley.co.uk/actuator/health | jq .
# Expected: {"status":"UP","components":{"toggle":{"status":"UP"},...}}

# List items
curl -sf https://fargate-test.edoatley.co.uk/api/items | jq .
# Expected: [{id, name, description}, ...]

# Fetch a specific item
curl -sf https://fargate-test.edoatley.co.uk/api/items/1 | jq .
```

---

## Step 6 — Run the load test

```bash
chmod +x scripts/examples/containerised-app-prod/aws.sh
./scripts/examples/containerised-app-prod/aws.sh
```

The script:
1. Looks up the ALB DNS name via AWS CLI (`--profile sandbox`)
2. Validates the health endpoint
3. Runs a quick items API smoke test
4. Drives 5 TPS for 30 seconds across `GET /api/items`
5. Forces a 404 via an unknown item ID
6. Toggles health DOWN, waits for the ALB to detect unhealthy targets (expect 503), then restores health
7. Tails the last 5 minutes of CloudWatch logs
8. Prints the ECS service running/desired/pending counts
9. Prints a pass/fail summary

Options:
```bash
./aws.sh --profile my-profile --hostname fargate-test.edoatley.co.uk
```

---

## AWS Console — where to look

### ECS
- **Clusters** → `tf-public-cloud-app-prod`
  - **Tasks** tab — running count, AZ spread, task health
  - Click a task → **Logs** tab — live CloudWatch log stream for that container
- **Task definitions** → `tf-public-cloud-app-prod` — CPU/memory allocation, image URI, health check command

### CloudWatch
- **Log groups** → `/ecs/tf-public-cloud-app-prod`
  - Filter by `ERROR` or `WARN` to find application errors
  - Each log stream is named `ecs/app/<task-id>`
- **Dashboards** → `tf-public-cloud-app-prod`
  - Row 1: Request Count, p99 Response Time, 5xx Errors
  - Row 2: ECS CPU %, ECS Memory %, Unhealthy Host Count
- **Alarms** — search prefix `tf-public-cloud-app-prod`:
  - `...-target-5xx` — any 5xx from ECS containers
  - `...-alb-5xx` — any 5xx generated by the ALB itself
  - `...-latency-p99` — p99 response time > 2 s (2-period evaluation)
  - `...-unhealthy-hosts` — any target marked unhealthy
  - `...-cpu-high` — service average CPU > 80% (2-period evaluation)

### EC2 / Load Balancing
- **Load Balancers** → `tf-public-cloud-app-prod-alb`
  - **Monitoring** tab — request count, latency, HTTP status breakdown
  - **Listeners** tab — HTTP:80 redirect rule, HTTPS:443 forward rule
- **Target Groups** → `tf-pub-cloud-app-prod-tg`
  - **Targets** tab — health status, AZ, and port of each Fargate task IP
  - Healthy threshold: 2 checks, unhealthy: 3 checks, interval: 30 s

### Route53
- **Hosted zones** → `fargate-test.edoatley.co.uk`
  - A alias record → ALB DNS name
  - CNAME records for ACM certificate validation

### ACM
- **Certificates** — find the certificate for `fargate-test.edoatley.co.uk`
  - Status should be `Issued`
  - Domain validation records should show as `Success`

---

## Teardown

Run these steps in order. Each step depends on the previous one completing successfully.

### 1. Destroy the app infrastructure

```bash
gh workflow run apply-resource.yml \
  --field resource_type=containerised-app-prod \
  --field cloud=aws \
  --field action=destroy \
  --ref release-1.0.0
gh run watch
```

This removes the ECS cluster/service/tasks, ALB, ACM certificate, Route53 A and cert-validation records, VPC and all subnets, NAT gateway, Elastic IP, IAM roles, auto-scaling policies, CloudWatch log group, alarms, and dashboard.

### 2. Destroy the container registry

The ECR repository and its images are not managed by the app module and must be destroyed separately:

```bash
gh workflow run apply-resource.yml \
  --field resource_type=container-registry \
  --field cloud=aws \
  --field action=destroy \
  --ref release-1.0.0
gh run watch
```

### 3. Delete the hosted zone in the sandbox account

The `fargate-test.edoatley.co.uk` hosted zone was created manually (Step 1a) and is not managed by Terraform, so it must be deleted manually.

```bash
# Look up the zone ID
ZONE_ID=$(aws route53 list-hosted-zones \
  --profile sandbox \
  --query "HostedZones[?Name=='fargate-test.edoatley.co.uk.'].Id" \
  --output text | sed 's|/hostedzone/||')
echo "Zone ID: ${ZONE_ID}"

# Delete any non-SOA/NS records first (ACM CNAMEs are removed by Terraform,
# but check nothing remains)
aws route53 list-resource-record-sets \
  --hosted-zone-id "${ZONE_ID}" \
  --profile sandbox \
  --query "ResourceRecordSets[?Type!='NS' && Type!='SOA']"

# Delete the hosted zone (only possible once empty of non-default records)
aws route53 delete-hosted-zone \
  --id "${ZONE_ID}" \
  --profile sandbox
```

### 4. Remove the NS delegation from the parent zone

In the **prod account** (705251932900), remove the NS record that delegated `fargate-test.edoatley.co.uk` to the sandbox hosted zone. Replace the four NS values with the actual values that were added in Step 1b.

```bash
PARENT_ZONE=$(aws route53 list-hosted-zones \
  --profile backups \
  --query "HostedZones[?Name=='edoatley.co.uk.'].Id" \
  --output text | sed 's|/hostedzone/||')

aws route53 change-resource-record-sets \
  --hosted-zone-id "${PARENT_ZONE}" \
  --profile backups \
  --change-batch '{
    "Changes": [{
      "Action": "DELETE",
      "ResourceRecordSet": {
        "Name": "fargate-test.edoatley.co.uk",
        "Type": "NS",
        "TTL": 300,
        "ResourceRecords": [
          {"Value": "ns-1355.awsdns-41.org."},
          {"Value": "ns-6.awsdns-00.com."},
          {"Value": "ns-595.awsdns-10.net."},
          {"Value": "ns-1911.awsdns-46.co.uk."}
        ]
      }
    }]
  }'
```

### Verify nothing remains

```bash
# Confirm no ECS cluster
aws ecs describe-clusters \
  --clusters tf-public-cloud-app-prod \
  --region eu-west-2 --profile sandbox \
  --query 'clusters[0].status'
# Expected: "INACTIVE" or an empty list

# Confirm no ALB
aws elbv2 describe-load-balancers \
  --names tf-public-cloud-app-prod-alb \
  --region eu-west-2 --profile sandbox 2>&1 | grep -i "not found\|LoadBalancerNotFound"
# Expected: error indicating the ALB does not exist

# Confirm no ECR repository
aws ecr describe-repositories \
  --repository-names tf-public-cloud-app \
  --region eu-west-2 --profile sandbox 2>&1 | grep -i "not found\|RepositoryNotFoundException"
# Expected: error indicating the repository does not exist

# Confirm subdomain no longer resolves
dig fargate-test.edoatley.co.uk A +short
# Expected: empty (NXDOMAIN)
```
