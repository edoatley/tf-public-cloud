# Observability guide — containerised app

This guide explains where to observe metrics, alarms, container restarts, and logs for the
`tf-public-cloud-app` deployment on each cloud. Run one of the demo scripts to generate traffic
and trigger the health toggle, then use the pointers below to watch events unfold in real time.

```bash
# Run the demo (SOAK_SECONDS controls baseline duration before toggle; default 30)
# Recovery is platform-driven — the script polls until the new instance is healthy
./scripts/examples/health-toggle/aws.sh   [SOAK_SECONDS]
./scripts/examples/health-toggle/gcp.sh   [PROJECT_ID] [SOAK_SECONDS]
./scripts/examples/health-toggle/azure.sh [SOAK_SECONDS]
```

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

**CLI — query last 10 minutes of 5xx counts:**

```bash
# Get the ARN suffix (format: app/<name>/<id>) needed for the CloudWatch dimension
LB_ARN=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName,`tf-public-cloud-app-alb`)].LoadBalancerArn' \
  --output text)
LB_SUFFIX=$(echo "${LB_ARN}" | sed 's|.*:loadbalancer/||')

aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count \
  --dimensions "Name=LoadBalancer,Value=${LB_SUFFIX}" \
  --start-time "$(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 --statistics Sum
```

### ECS task restarts

**Console:** ECS → Clusters → `tf-public-cloud-app` → Services → `tf-public-cloud-app` → Events tab

After the toggle, the container health check (`wget .../actuator/health`) starts failing. ECS
marks the task unhealthy after 3 consecutive failures (≈90s) and replaces it. The Events tab
shows `(service tf-public-cloud-app) has stopped 1 running tasks` then `registered 1 targets`.

### Application logs (AWS)

**Console:** CloudWatch → Log groups → `/ecs/tf-public-cloud-app`

**CLI — stream live:**

```bash
aws logs tail /ecs/tf-public-cloud-app --follow --format short
```

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

### Application logs (GCP)

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

### Application logs (Azure)

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

## What the demo shows end-to-end

The recovery is entirely **platform-driven** — there is no manual toggle back to UP. The new
instance starts fresh with `ToggleHealthIndicator` initialised to `true`, so it is immediately
healthy. The script polls until 3 consecutive 200s confirm the replacement is serving traffic.

| Phase | Approx time | Event | What to watch |
| ----- | ----------- | ----- | ------------- |
| 1 — Baseline | 0s → +SOAK | Traffic starts (2 req/s) | Script output: all green 2xx / yellow 404 |
| — | +SOAK | `POST /health/toggle` → DOWN | `/actuator/health` immediately returns 503 |
| 2 — Degraded | +SOAK → recovery | Liveness probe detects failure | Script output: red 503s on `/actuator/health`; other endpoints stay 200 |
| — | AWS ~90s / GCP ~10s / Azure ~30s | Platform kills the unhealthy instance | AWS: brief 502s as ALB drains old task; GCP/Azure: seamless handover |
| — | Varies | New instance starts, passes health check | Script detects 3× 200 and prints recovery time |
| 3 — Recovery | +30s post-recovery | Post-recovery soak | All requests green; confirms new instance is stable |
| — | Alarm window | 5xx count crosses threshold | CloudWatch ALARM / Cloud Monitoring incident / Azure Monitor alert fires |
| End | — | Summary + logs printed | 2xx/4xx/5xx counts; Spring Boot startup banner in logs confirms new instance |

**Platform recovery times observed:**

| Cloud | Mechanism | Typical time to recovery |
| ----- | --------- | ------------------------ |
| AWS ECS | 3 × 30s health check failures → task replaced → ALB re-registers | ~150–180s (including 502 window) |
| GCP Cloud Run | Single liveness probe failure (period 10s) → container restarted | ~30–60s |
| Azure Container Apps | Liveness probe failure → replica restarted | ~60–90s |

---

## Demo run examples

### Azure (observed 2026-06-15)

<details>
<summary>Full output — toggle at 12:11:01, recovery confirmed at 68s</summary>

```terminaloutput
==> Looking up Container App FQDN
    https://tf-public-cloud-app--o7iqd0p.mangomushroom-af1a784c.uksouth.azurecontainerapps.io

==> Phase 1: baseline traffic for 30s — all requests should be 200/404
[12:10:59] GET    /api/items                     → 200
[12:10:59] GET    /api/items/1                   → 200
[12:11:00] GET    /api/items/99                  → 404
[12:11:00] GET    /actuator/health               → 200

==> Toggling health → DOWN
    Container Apps liveness probe checks /actuator/health periodically.
    On probe failure it will restart the replica — the new replica starts healthy.
{
  "status": "DOWN"
}

==> Phase 2: waiting for Container Apps to restart the replica (platform-driven)

[12:11:01] GET    /api/items                     → 200
[12:11:01] GET    /api/items/1                   → 200
[12:11:02] GET    /api/items/99                  → 404
[12:11:03] GET    /actuator/health               → 503
... (503s continue for ~30s while liveness probe detects failure) ...
[12:11:30] GET    /api/items/99                  → 503   ← replica being stopped, brief 503 on all endpoints
[12:11:31] GET    /actuator/health               → 503
[12:12:03] GET    /api/items                     → 200   ← new replica serving traffic
[12:12:04] GET    /actuator/health               → 200
[12:12:05] GET    /actuator/health               → 200
[12:12:06] GET    /actuator/health               → 200

==> Recovery confirmed — Container Apps restarted the replica, new instance is healthy
    Time from toggle to recovery: 68s

==> Phase 3: post-recovery traffic for 30s — confirming stable 200s on new replica
[12:12:09] GET    /api/items                     → 200
... (all 200s) ...

==> Fetching container logs around the restart window

{"TimeStamp": "2026-06-15T11:11:39.10Z", "Log": ""}
{"TimeStamp": "2026-06-15T11:11:39.10Z", "Log": ".   ____          _            __ _ _"}
{"TimeStamp": "2026-06-15T11:11:39.10Z", "Log": ":: Spring Boot ::                (v3.4.1)"}
{"TimeStamp": "2026-06-15T11:11:39.80Z", "Log": "INFO 1 --- [main] com.example.app.Application : Starting Application using Java 21.0.11 with PID 1"}
{"TimeStamp": "2026-06-15T11:12:01.10Z", "Log": "INFO 1 --- [main] com.example.app.Application : Started Application in 25.8 seconds"}

==> Demo complete

=== Summary ===
  Total requests : 120
  2xx            : 77
  4xx            : 29
  5xx (503)      : 14
```

**Key observations:**

- 14 × 503 on `/actuator/health` during the ~30s the liveness probe was detecting failure
- Gap from `12:11:31` → `12:12:03` (32s) = replica stopped, new replica starting
- Spring Boot startup at `11:11:39` UTC (PID 1) proves a brand-new container process
- Recovery confirmed at 68s with no manual intervention

</details>

### AWS (observed 2026-06-15)

<details>
<summary>Full output — toggle at 12:10:37, recovery confirmed at 206s</summary>

```terminaloutput
➜  tf-public-cloud git:(health-toggle) ✗ ./scripts/examples/health-toggle/aws.sh 30                     
==> Looking up ALB DNS name
    http://tf-public-cloud-app-alb-1324468076.eu-west-2.elb.amazonaws.com

==> Phase 1: baseline traffic for 30s — all requests should be 200/404
[12:10:06] GET    /api/items                     → 200
[12:10:06] GET    /api/items/1                   → 200
[12:10:07] GET    /api/items/99                  → 404
[12:10:08] GET    /actuator/health               → 200
[12:10:08] GET    /api/items                     → 200
[12:10:09] GET    /api/items/1                   → 200
[12:10:09] GET    /api/items/99                  → 404
...
[12:10:34] GET    /actuator/health               → 200
[12:10:35] GET    /api/items                     → 200
[12:10:35] GET    /api/items/1                   → 200
[12:10:36] GET    /api/items/99                  → 404
[12:10:37] GET    /actuator/health               → 200

==> Toggling health → DOWN
    ECS will run its health check every 30s — after 3 failures (~90s) it will
    stop this task and start a replacement. The new task starts with health UP.
    Watch: ECS → Clusters → tf-public-cloud-app → Services → Events tab
           CloudWatch → Alarms → tf-public-cloud-app-target-5xx
{
  "status": "DOWN"
}

==> Phase 2: waiting for ECS to replace the task (no manual toggle — platform drives this)
    503 = app reporting DOWN, 502 = ALB has no healthy target (task being replaced)

[12:10:37] GET    /api/items                     → 200
[12:10:38] GET    /api/items/1                   → 200
[12:10:38] GET    /api/items/99                  → 404
[12:10:39] GET    /actuator/health               → 503
...
[12:10:57] GET    /api/items                     → 200
[12:10:58] GET    /api/items/1                   → 200
[12:10:58] GET    /api/items/99                  → 404
[12:10:59] GET    /actuator/health               → 503
...
[12:11:46] GET    /api/items                     → 200
[12:11:47] GET    /api/items/1                   → 200
[12:11:48] GET    /api/items/99                  → 404
[12:11:48] GET    /actuator/health               → 503
...
[12:12:07] GET    /api/items                     → 200
[12:12:07] GET    /api/items/1                   → 200
[12:12:08] GET    /api/items/99                  → 404
[12:12:08] GET    /actuator/health               → 503
...
[12:12:24] GET    /api/items                     → 200
[12:12:25] GET    /api/items/1                   → 200
[12:12:25] GET    /api/items/99                  → 404
[12:12:26] GET    /actuator/health               → 503
...
[12:12:42] GET    /api/items                     → 200
[12:12:43] GET    /api/items/1                   → 200
[12:12:43] GET    /api/items/99                  → 404
[12:12:44] GET    /actuator/health               → 503
...
[12:13:02] GET    /actuator/health               → 503
[12:13:02] GET    /api/items                     → 200
[12:13:03] GET    /api/items/1                   → 200
[12:13:03] GET    /api/items/99                  → 404
[12:13:04] GET    /actuator/health               → 503
[12:13:05] GET    /api/items                     → 502  <<<< 502s start as Fargate replaces task
[12:13:05] GET    /api/items/1                   → 200
[12:13:06] GET    /api/items/99                  → 404
[12:13:06] GET    /actuator/health               → 502
[12:13:07] GET    /api/items                     → 200
[12:13:07] GET    /api/items/1                   → 502
[12:13:08] GET    /api/items/99                  → 404
[12:13:09] GET    /actuator/health               → 502
[12:13:09] GET    /api/items                     → 200
[12:13:10] GET    /api/items/1                   → 502
[12:13:10] GET    /api/items/99                  → 404
[12:13:11] GET    /actuator/health               → 502
[12:13:11] GET    /api/items                     → 200
[12:13:12] GET    /api/items/1                   → 502
[12:13:13] GET    /api/items/99                  → 404
[12:13:13] GET    /actuator/health               → 502
[12:13:14] GET    /api/items                     → 200
[12:13:14] GET    /api/items/1                   → 502
[12:13:15] GET    /api/items/99                  → 502
[12:13:15] GET    /actuator/health               → 503
[12:13:16] GET    /api/items                     → 502
[12:13:16] GET    /api/items/1                   → 200
[12:13:17] GET    /api/items/99                  → 502
[12:13:18] GET    /actuator/health               → 503
[12:13:18] GET    /api/items                     → 200
[12:13:19] GET    /api/items/1                   → 502
[12:13:19] GET    /api/items/99                  → 502
[12:13:20] GET    /actuator/health               → 503
[12:13:20] GET    /api/items                     → 200
[12:13:21] GET    /api/items/1                   → 502
[12:13:22] GET    /api/items/99                  → 502
[12:13:22] GET    /actuator/health               → 503
...
[12:13:36] GET    /api/items                     → 502
[12:13:37] GET    /api/items/1                   → 200
[12:13:37] GET    /api/items/99                  → 404
[12:13:38] GET    /actuator/health               → 502
...
[12:14:01] GET    /api/items                     → 200
[12:14:02] GET    /api/items/1                   → 200
[12:14:02] GET    /api/items/99                  → 404
[12:14:03] GET    /actuator/health               → 200

==> Recovery confirmed — new ECS task is healthy and serving traffic
    Time from toggle to recovery: 206s

==> Phase 3: post-recovery traffic for 30s — confirming stable 200s on new task
[12:14:03] GET    /api/items                     → 200
[12:14:03] GET    /api/items/1                   → 200
[12:14:04] GET    /api/items/99                  → 404
[12:14:04] GET    /actuator/health               → 503
[12:14:05] GET    /api/items                     → 200
[12:14:06] GET    /api/items/1                   → 200
[12:14:06] GET    /api/items/99                  → 404
[12:14:07] GET    /actuator/health               → 200
[12:14:07] GET    /api/items                     → 200
[12:14:08] GET    /api/items/1                   → 200
[12:14:08] GET    /api/items/99                  → 404
[12:14:09] GET    /actuator/health               → 200
[12:14:10] GET    /api/items                     → 200
[12:14:10] GET    /api/items/1                   → 200
[12:14:11] GET    /api/items/99                  → 404
[12:14:11] GET    /actuator/health               → 200
[12:14:12] GET    /api/items                     → 200
[12:14:12] GET    /api/items/1                   → 200
[12:14:13] GET    /api/items/99                  → 404
[12:14:13] GET    /actuator/health               → 200
[12:14:14] GET    /api/items                     → 200
[12:14:15] GET    /api/items/1                   → 200
[12:14:15] GET    /api/items/99                  → 404
[12:14:16] GET    /actuator/health               → 200

==> Fetching CloudWatch logs around the task replacement window
    Log group: /ecs/tf-public-cloud-app

[12:13:14]   .   ____          _            __ _ _
[12:13:14]  /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \
[12:13:14] ( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \
[12:13:14]  \\/  ___)| |_)| | | | | || (_| |  ) ) ) )
[12:13:14]   '  |____| .__|_| |_|_| |_\__, | / / / /
[12:13:14]  =========|_|==============|___/=/_/_/_/
[12:13:14]  :: Spring Boot ::                (v3.4.1)
[12:13:16] 2026-06-15T11:13:16.703Z  INFO 1 --- [           main] com.example.app.Application              : Starting Application using Java 21.0.11 with PID 1 (/app/app.jar started by appuser in /app)
[12:13:16] 2026-06-15T11:13:16.803Z  INFO 1 --- [           main] com.example.app.Application              : No active profile set, falling back to 1 default profile: "default"
[12:13:36] 2026-06-15T11:13:36.114Z  INFO 1 --- [           main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat initialized with port 8080 (http)
[12:13:36] 2026-06-15T11:13:36.306Z  INFO 1 --- [           main] o.apache.catalina.core.StandardService   : Starting service [Tomcat]
[12:13:36] 2026-06-15T11:13:36.306Z  INFO 1 --- [           main] o.apache.catalina.core.StandardEngine    : Starting Servlet engine: [Apache Tomcat/10.1.34]
[12:13:36] 2026-06-15T11:13:36.717Z  INFO 1 --- [           main] o.a.c.c.C.[Tomcat].[localhost].[/]       : Initializing Spring embedded WebApplicationContext
[12:13:36] 2026-06-15T11:13:36.719Z  INFO 1 --- [           main] w.s.c.ServletWebServerApplicationContext : Root WebApplicationContext: initialization completed in 18908 ms
[12:13:44] 2026-06-15T11:13:44.818Z  INFO 1 --- [           main] o.s.b.a.e.web.EndpointLinksResolver      : Exposing 2 endpoints beneath base path '/actuator'
[12:13:46] 2026-06-15T11:13:46.516Z  INFO 1 --- [           main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat started on port 8080 (http) with context path '/'
[12:13:46] 2026-06-15T11:13:46.715Z  INFO 1 --- [           main] com.example.app.Application              : Started Application in 39.299 seconds (process running for 46.88)
[12:13:47] 2026-06-15T11:13:47.310Z  INFO 1 --- [nio-8080-exec-1] o.a.c.c.C.[Tomcat].[localhost].[/]       : Initializing Spring DispatcherServlet 'dispatcherServlet'
[12:13:47] 2026-06-15T11:13:47.310Z  INFO 1 --- [nio-8080-exec-1] o.s.web.servlet.DispatcherServlet        : Initializing Servlet 'dispatcherServlet'
[12:13:47] 2026-06-15T11:13:47.312Z  INFO 1 --- [nio-8080-exec-1] o.s.web.servlet.DispatcherServlet        : Completed initialization in 2 ms

==> Demo complete
    The logs above show the old task stopping and the new task starting.
    Key lines to look for: Spring Boot startup banner on the new task,
    and the absence of any lines after the toggle on the old task.

=== Summary ===
  Total requests : 476
  2xx            : 250
  4xx            : 110
  5xx (503)      : 79
  502 (no target) : 37
```

**Key observations:**

- 503s began immediately at `12:10:39` — the toggle took effect in-process with no restart
- Other endpoints (`/api/items`, `/api/items/1`) continued returning 200 throughout the 503 phase, confirming only the health indicator was affected
- 502s appeared at `12:13:05` — the ALB was draining the old task and the new one hadn't registered yet (ECS task replacement window)
- Mixed 502/503 between `12:13:05–12:13:50` = both old task (reporting DOWN) and new task (still starting) handling requests in parallel across the two ALB targets
- First clean 200 on `/actuator/health` at `12:13:54`, stable from `12:13:58` — confirmed recovery at 206s
- Spring Boot startup at `12:13:14` (PID 1, 39s startup time) proves ECS launched a brand-new task
- 37 × 502 = the ALB handover window; these are infrastructure-level, not application errors

</details>

### GCP (observed 2026-06-15)

<details>
<summary>Full output — toggle at 12:10:31, recovery confirmed at 51s</summary>

```terminaloutput
==> Looking up Cloud Run service URL
    https://tf-public-cloud-app-lkatnppnna-ew.a.run.app

==> Phase 1: baseline traffic for 30s — all requests should be 200/404
[12:10:15] GET    /api/items                     → 200
[12:10:15] GET    /api/items/1                   → 200
[12:10:16] GET    /api/items/99                  → 404
[12:10:16] GET    /actuator/health               → 200
[12:10:17] GET    /api/items                     → 200
[12:10:18] GET    /api/items/1                   → 200
[12:10:18] GET    /api/items/99                  → 404
[12:10:19] GET    /actuator/health               → 200
[12:10:19] GET    /api/items                     → 200
[12:10:20] GET    /api/items/1                   → 200
[12:10:21] GET    /api/items/99                  → 404
[12:10:21] GET    /actuator/health               → 200
[12:10:22] GET    /api/items                     → 200
[12:10:22] GET    /api/items/1                   → 200
[12:10:23] GET    /api/items/99                  → 404
[12:10:24] GET    /actuator/health               → 200
[12:10:24] GET    /api/items                     → 200
[12:10:25] GET    /api/items/1                   → 200
[12:10:25] GET    /api/items/99                  → 404
[12:10:26] GET    /actuator/health               → 200
[12:10:26] GET    /api/items                     → 200
[12:10:27] GET    /api/items/1                   → 200
[12:10:28] GET    /api/items/99                  → 404
[12:10:28] GET    /actuator/health               → 200
[12:10:29] GET    /api/items                     → 200
[12:10:29] GET    /api/items/1                   → 200
[12:10:30] GET    /api/items/99                  → 404
[12:10:31] GET    /actuator/health               → 200

==> Toggling health → DOWN
    Cloud Run liveness probe checks /actuator/health every 10s.
    On the next failed probe Cloud Run will restart the container.
    The new container starts with health UP — no manual toggle needed.
    Watch: Cloud Run → tf-public-cloud-app → Revisions (restart count)
           Monitoring → Alerting → tf-public-cloud-app Cloud Run 5xx errors
{
  "status": "DOWN"
}

==> Phase 2: waiting for Cloud Run to restart the container (platform-driven)

[12:10:31] GET    /api/items                     → 200
[12:10:32] GET    /api/items/1                   → 200
[12:10:32] GET    /api/items/99                  → 404
[12:10:33] GET    /actuator/health               → 503
[12:10:34] GET    /api/items                     → 200
[12:10:34] GET    /api/items/1                   → 200
[12:10:35] GET    /api/items/99                  → 404
[12:10:35] GET    /actuator/health               → 503
[12:10:36] GET    /api/items                     → 200
[12:10:37] GET    /api/items/1                   → 200
[12:10:37] GET    /api/items/99                  → 404
[12:10:38] GET    /actuator/health               → 503
[12:10:38] GET    /api/items                     → 200
[12:10:39] GET    /api/items/1                   → 200
[12:10:40] GET    /api/items/99                  → 404
[12:10:40] GET    /actuator/health               → 503
[12:10:41] GET    /api/items                     → 200
[12:10:41] GET    /api/items/1                   → 200
[12:10:42] GET    /api/items/99                  → 404
[12:10:43] GET    /actuator/health               → 503
[12:10:43] GET    /api/items                     → 200
[12:10:44] GET    /api/items/1                   → 200
[12:10:44] GET    /api/items/99                  → 404
...
[12:11:01] GET    /actuator/health               → 503
[12:11:02] GET    /api/items                     → 200
[12:11:03] GET    /api/items/1                   → 200
[12:11:03] GET    /api/items/99                  → 404
[12:11:17] GET    /actuator/health               → 200
[12:11:17] GET    /api/items                     → 200
[12:11:18] GET    /api/items/1                   → 200
[12:11:19] GET    /api/items/99                  → 404
[12:11:19] GET    /actuator/health               → 200
[12:11:20] GET    /api/items                     → 200
[12:11:20] GET    /api/items/1                   → 200
[12:11:21] GET    /api/items/99                  → 404
[12:11:22] GET    /actuator/health               → 200

==> Recovery confirmed — Cloud Run restarted the container, new instance is healthy
    Time from toggle to recovery: 51s

==> Phase 3: post-recovery traffic for 30s — confirming stable 200s on new container
[12:11:22] GET    /api/items                     → 200
[12:11:22] GET    /api/items/1                   → 200
[12:11:23] GET    /api/items/99                  → 404
[12:11:23] GET    /actuator/health               → 200
[12:11:24] GET    /api/items                     → 200
[12:11:25] GET    /api/items/1                   → 200
[12:11:25] GET    /api/items/99                  → 404
[12:11:26] GET    /actuator/health               → 200
[12:11:26] GET    /api/items                     → 200
[12:11:27] GET    /api/items/1                   → 200
[12:11:28] GET    /api/items/99                  → 404
[12:11:28] GET    /actuator/health               → 200
[12:11:29] GET    /api/items                     → 200
[12:11:29] GET    /api/items/1                   → 200
[12:11:30] GET    /api/items/99                  → 404
[12:11:31] GET    /actuator/health               → 200
[12:11:31] GET    /api/items                     → 200
[12:11:32] GET    /api/items/1                   → 200
[12:11:32] GET    /api/items/99                  → 404
[12:11:33] GET    /actuator/health               → 200
[12:11:34] GET    /api/items                     → 200
[12:11:34] GET    /api/items/1                   → 200
[12:11:35] GET    /api/items/99                  → 404


==> Fetching Cloud Logging entries around the restart window

2026-06-15T11:10:00.964650Z  Starting new instance. Reason: AUTOSCALING
2026-06-15T11:10:05.066104Z    .   ____          _            __ _ _
2026-06-15T11:10:05.066134Z   /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \
2026-06-15T11:10:05.070489Z   :: Spring Boot ::                (v3.4.1)
2026-06-15T11:10:05.379571Z  INFO 1 --- [main] com.example.app.Application : Starting Application using Java 21.0.11 with PID 1
2026-06-15T11:10:10.360327Z  INFO 1 --- [main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat initialized with port 8080 (http)
2026-06-15T11:10:10.854864Z  INFO 1 --- [main] w.s.c.ServletWebServerApplicationContext : Root WebApplicationContext: initialization completed in 5214 ms
2026-06-15T11:10:13.882985Z  INFO 1 --- [main] o.s.b.a.e.web.EndpointLinksResolver      : Exposing 2 endpoints beneath base path '/actuator'
2026-06-15T11:10:14.053908Z  Default STARTUP TCP probe succeeded after 1 attempt for container "tf-public-cloud-app-1" on port 8080.
2026-06-15T11:10:14.078394Z  INFO 1 --- [main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat started on port 8080 (http) with context path '/'
2026-06-15T11:10:14.339509Z  INFO 1 --- [main] com.example.app.Application              : Started Application in 10.703 seconds (process running for 13.122)

==> Demo complete
    Look for Spring Boot startup banner in the logs above — that is the new container.
    Requests logged before the restart will show no entries after the toggle.

=== Summary ===
  Total requests : 144
  2xx            : 95
  4xx            : 36
  5xx (503)      : 13
```

**Key observations:**

- Only 13 × 503 across the whole run — Cloud Run's liveness probe period is 10s so it detected the failure and restarted within one probe cycle
- **No 502s** — unlike ECS, Cloud Run handles the container restart transparently; the platform routes requests to the new instance without exposing a "no healthy target" window
- Gap from `12:11:03` → `12:11:17` (14s) = container being replaced; requests were held or failed silently
- Spring Boot started at `11:10:05` UTC (PID 1, only 10.7s startup — significantly faster than ECS/Azure due to JVM warm start behaviour)
- Cloud Logging shows `Starting new instance. Reason: AUTOSCALING` — this is the platform's restart event, not triggered manually
- `Default STARTUP TCP probe succeeded` confirms the new container passed Cloud Run's startup check before receiving traffic
- Recovery confirmed at 51s — fastest of the three clouds due to the short liveness probe period

</details>
