# Observability guide — containerised app

This guide explains where to observe metrics, alarms, container restarts, and logs for the
`tf-public-cloud-app` deployment on each cloud. Run one of the demo scripts to generate traffic
and trigger the health toggle, then use the pointers below to watch events unfold in real time.

```bash
# Run the demo (defaults: 30s soak → toggle DOWN → 60s → toggle UP → 30s recovery)
./scripts/demo/health-toggle-demo-aws.sh
./scripts/demo/health-toggle-demo-gcp.sh   [PROJECT_ID]
./scripts/demo/health-toggle-demo-azure.sh
```

---

## AWS

### CloudWatch alarm
**Console:** CloudWatch → Alarms → `tf-public-cloud-app-target-5xx`

The alarm monitors `HTTPCode_Target_5XX_Count` on the ALB/target group pair. It transitions
`OK → ALARM` within one 60-second evaluation period after the first 5xx response lands.

### ALB request metrics
**Console:** EC2 → Load Balancers → `tf-public-cloud-app-alb` → Monitoring tab

Key metrics to watch:
- `HTTPCode_Target_5XX_Count` — spikes after toggle, drops after recovery
- `HTTPCode_Target_2XX_Count` — drops during the DOWN phase
- `TargetResponseTime` — may spike briefly during task replacement
- `RequestCount` — flat throughout (traffic keeps flowing to the ALB)

**CLI — tail live metrics (1-minute datapoints):**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count \
  --dimensions Name=LoadBalancer,Value=$(aws elbv2 describe-load-balancers \
      --names tf-public-cloud-app-alb \
      --query 'LoadBalancers[0].LoadBalancerArn' --output text | sed 's|.*loadbalancer/||') \
  --start-time "$(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 --statistics Sum
```

### ECS task restarts
**Console:** ECS → Clusters → `tf-public-cloud-app` → Services → `tf-public-cloud-app` → Events tab

After the toggle, the container health check (`wget .../actuator/health`) starts failing. ECS
marks the task unhealthy after 3 consecutive failures (≈90s) and replaces it. The Events tab
shows `(service tf-public-cloud-app) has stopped 1 running tasks` then `registered 1 targets`.

### Application logs
**Console:** CloudWatch → Log groups → `/ecs/tf-public-cloud-app`

**CLI — stream live:**
```bash
aws logs tail /ecs/tf-public-cloud-app --follow --format short
```

---

## GCP

### Cloud Monitoring alert
**Console:** Cloud Console → Monitoring → Alerting

Look for the policy `tf-public-cloud-app Cloud Run 5xx errors`. It fires within ~2 minutes of
the first 5xx traffic (60s alignment window + propagation delay). The **Incidents** tab shows
open and resolved incidents with start/end times.

### Cloud Run request metrics
**Console:** Cloud Run → `tf-public-cloud-app` → Metrics tab

Key charts:
- **Request count** — switch the breakdown to `Response code class`; the `5xx` series
  appears after the toggle and disappears after recovery
- **Request latency** — may show elevated p99 during restart
- **Container instance count** — drops to 0 briefly then recovers (min-instances = 0)

**CLI — query recent 5xx count:**
```bash
gcloud logging read \
  'resource.type="cloud_run_revision"
   resource.labels.service_name="tf-public-cloud-app"
   httpRequest.status>=500' \
  --limit 20 \
  --format "table(timestamp, httpRequest.status, httpRequest.requestUrl)"
```

### Revision restarts
**Console:** Cloud Run → `tf-public-cloud-app` → Revisions

The **Instances** column shows restart count. After the liveness probe (`/actuator/health`)
returns 503 for `period_seconds` (10s), Cloud Run kills and restarts the container. The restart
count for the active revision increments.

### Application logs
**Console:** Logging → Logs Explorer

Filter:
```
resource.type="cloud_run_revision"
resource.labels.service_name="tf-public-cloud-app"
```

**CLI:**
```bash
gcloud logging read \
  'resource.type=cloud_run_revision AND resource.labels.service_name=tf-public-cloud-app' \
  --limit 50 --format json | jq '.[].textPayload'
```

---

## Azure

### Azure Monitor alert
**Portal:** Monitor → Alerts → Alert rules → `tf-public-cloud-app-5xx-alert`

The alert evaluates every 1 minute over a 5-minute window. It fires within 5 minutes of
sustained 5xx traffic. The **Alert history** tab shows fired and resolved alerts with timestamps.

**CLI — check current alert state:**
```bash
az monitor metrics alert show \
  --name "tf-public-cloud-app-5xx-alert" \
  --resource-group "$(az containerapp list \
      --query "[?name=='tf-public-cloud-app'].resourceGroup | [0]" --output tsv)"
```

### Container App request metrics
**Portal:** Container Apps → `tf-public-cloud-app` → Metrics

Add the following metrics:
- **Requests** — split by `Status Code Category` to see 2xx/4xx/5xx as separate series
- **Replica count** — shows the restart dip

**Portal shortcut:** in the Metrics blade, select `Requests`, click **Apply splitting**,
choose `Status Code Category`.

### Replica restarts
**Portal:** Container Apps → `tf-public-cloud-app` → Revision management

After the liveness probe (`/actuator/health`) returns 503, Container Apps restarts the replica.
The replica count in the Revisions view briefly drops to 0 then recovers.

### Application logs
**Portal:** Container Apps → `tf-public-cloud-app` → Log stream (live tail)

**Log Analytics query** (Portal → Monitor → Logs, or the app's Log Analytics workspace):
```kusto
ContainerAppConsoleLogs
| where ContainerAppName == "tf-public-cloud-app"
| order by TimeGenerated desc
| take 50
```

**CLI:**
```bash
az containerapp logs show \
  --name "tf-public-cloud-app" \
  --resource-group "$(az containerapp list \
      --query "[?name=='tf-public-cloud-app'].resourceGroup | [0]" --output tsv)" \
  --follow
```

---

## What the demo shows end-to-end

| Time | Event | What to watch |
|------|-------|---------------|
| 0s | Traffic starts (2 req/s) | Script output: all green 2xx |
| +30s | `POST /health/toggle` → DOWN | Script output turns red; `/actuator/health` → 503 |
| +30–90s | Liveness probe detects failure | ECS Events / Cloud Run Revisions / ACA Revisions |
| +60–90s | Platform restarts instance | Brief gap then green again (app restarts) |
| Alarm window | 5xx count crosses threshold | CloudWatch ALARM / Cloud Monitoring incident / Azure Monitor alert fires |
| +90s | `POST /health/toggle` → UP | 503s stop; platform considers new instance healthy |
| +120s | Recovery traffic | All green; alarms auto-resolve after their evaluation window |
| End | Summary printed | Count of 2xx / 4xx / 5xx confirms the failure window |
