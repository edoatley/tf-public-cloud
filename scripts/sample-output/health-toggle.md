# Health Toggle Demo — Sample Output

The health-toggle demo scripts show platform-driven self-healing. After a baseline soak,
the app's `/health/toggle` endpoint is called to force it into a DOWN state. The script
then polls until the platform detects the failure and replaces the instance — with no
manual intervention. Three phases are shown: baseline, recovery, and post-recovery.

## AWS (ECS Fargate — ~150s recovery)

ECS health check: interval=30s, retries=3 → ~90s to declare unhealthy. New task start +
ALB target registration adds ~60s.

```
$ bash scripts/examples/health-toggle/aws.sh 30

==> Looking up ALB DNS name
    http://tf-public-cloud-app-alb-1570170617.eu-west-2.elb.amazonaws.com

==> Phase 1: baseline traffic for 30s — all requests should be 200/404
[17:00:01] GET    /api/items                     → 200
[17:00:02] GET    /api/items/1                   → 200
[17:00:02] GET    /api/items/99                  → 404
[17:00:03] GET    /actuator/health               → 200
[17:00:03] GET    /api/items                     → 200
[17:00:04] GET    /api/items/1                   → 200
[17:00:04] GET    /api/items/99                  → 404
[17:00:05] GET    /actuator/health               → 200
... (requests continue at ~2/s for 30s)

==> Toggling health → DOWN
    ECS health check runs every 30s — after 3 failures (~90s) ECS stops
    this task and starts a replacement. The new task starts with health UP.
    Watch: ECS → Clusters → tf-public-cloud-app → Services → Events tab
           CloudWatch → Alarms → tf-public-cloud-app-target-5xx
{"status": "DOWN"}

==> Phase 2: waiting for platform to replace the instance (no manual toggle)
    503 = app reporting DOWN, 502 = no healthy target during handover

[17:00:36] GET    /api/items                     → 503
[17:00:37] GET    /api/items/1                   → 503
[17:00:37] GET    /api/items/99                  → 503
[17:00:38] GET    /actuator/health               → 503
... (503s continue while ECS health check detects failure — ~90s)
[17:02:06] GET    /api/items                     → 502
[17:02:07] GET    /api/items/1                   → 502
[17:02:07] GET    /api/items/99                  → 502
... (502s while old task is stopped and new task registers with ALB — ~60s)
[17:03:12] GET    /actuator/health               → 200
[17:03:13] GET    /actuator/health               → 200
[17:03:14] GET    /actuator/health               → 200

==> Recovery confirmed — new ECS task is healthy and serving traffic
    Time from toggle to recovery: 156s

==> Phase 3: post-recovery traffic for 30s — confirming stable 200s
[17:03:15] GET    /api/items                     → 200
[17:03:15] GET    /api/items/1                   → 200
[17:03:16] GET    /api/items/99                  → 404
[17:03:16] GET    /actuator/health               → 200
... (all 200/404 for 30s)

==> Fetching logs around the replacement window
    Log group: /ecs/tf-public-cloud-app

[17:00:05] Started GET /actuator/health
[17:00:35] Health toggled to DOWN
[17:00:36] Started GET /actuator/health -> 503
...
[17:02:10] Stopping container (old task)
[17:03:10]   .   ____          _            __ _ _
[17:03:10]  /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \
[17:03:10] ( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \
[17:03:10]  \\/  ___)| |_)| | | | | || (_| |  ) ) ) )
[17:03:10]   '  |____| .__|_| |_|_| |_\__, | / / / /
[17:03:10]  =========|_|==============|___/=/_/_/_/
[17:03:10]  :: Spring Boot ::  (new task startup banner)
[17:03:11] Started Application in 1.843 seconds

==> Demo complete
    Look for the Spring Boot startup banner — that is the new instance.
    The timestamp gap around the toggle confirms the old instance was stopped.

=== Summary ===
  Total requests : 287
  2xx             : 201
  4xx             : 42
  5xx (503)       : 28
  502 (no target) : 16
```

## GCP (Cloud Run — ~30s recovery)

Cloud Run liveness probe: period=10s → single failed probe triggers immediate container
restart. New container starts with health UP.

```
$ bash scripts/examples/health-toggle/gcp.sh 30

==> Looking up Cloud Run service URL
    https://tf-public-cloud-app-lkatnppnna-ew.a.run.app

==> Phase 1: baseline traffic for 30s — all requests should be 200/404
[17:00:01] GET    /api/items                     → 200
[17:00:02] GET    /api/items/1                   → 200
[17:00:02] GET    /api/items/99                  → 404
[17:00:03] GET    /actuator/health               → 200
... (requests continue at ~2/s for 30s)

==> Toggling health → DOWN
    Cloud Run liveness probe checks /actuator/health every 10s.
    On the next failed probe Cloud Run restarts the container immediately.
    The new container starts with health UP — no manual toggle needed.
    Watch: Cloud Run → tf-public-cloud-app → Revisions (restart count)
           Monitoring → Alerting → tf-public-cloud-app Cloud Run 5xx errors
{"status": "DOWN"}

==> Phase 2: waiting for platform to replace the instance (no manual toggle)
    503 = app reporting DOWN

[17:00:36] GET    /api/items                     → 503
[17:00:37] GET    /api/items/1                   → 503
... (503s until liveness probe fires — up to 10s)
[17:00:46] GET    /api/items                     → 200
[17:00:46] GET    /api/items/1                   → 200
[17:00:47] GET    /actuator/health               → 200
[17:00:47] GET    /actuator/health               → 200
[17:00:48] GET    /actuator/health               → 200

==> Recovery confirmed — Cloud Run restarted the container, new instance is healthy
    Time from toggle to recovery: 31s

==> Phase 3: post-recovery traffic for 30s — confirming stable 200s
[17:00:49] GET    /api/items                     → 200
...

==> Fetching logs around the replacement window
2026-06-18T17:00:35Z Health toggled to DOWN
2026-06-18T17:00:36Z GET /actuator/health 503
2026-06-18T17:00:46Z Started Application in 1.612 seconds (JVM running for 2.1)
2026-06-18T17:00:46Z GET /actuator/health 200

==> Demo complete
    Look for the Spring Boot startup banner — that is the new instance.
    The timestamp gap around the toggle confirms the old instance was restarted.

=== Summary ===
  Total requests : 198
  2xx             : 183
  4xx             : 10
  5xx (503)       : 5
  502 (no target) : 0
```

## Azure (Container Apps — ~60s recovery)

Container Apps liveness probe: period ~10s → replica restarted on probe failure.

```
$ bash scripts/examples/health-toggle/azure.sh 30

==> Looking up Container App FQDN
    https://tf-public-cloud-app--6w5jnmm.redcliff-6e6eca9f.uksouth.azurecontainerapps.io

==> Phase 1: baseline traffic for 30s — all requests should be 200/404
[17:00:01] GET    /api/items                     → 200
[17:00:02] GET    /api/items/1                   → 200
[17:00:02] GET    /api/items/99                  → 404
[17:00:03] GET    /actuator/health               → 200
... (requests continue at ~2/s for 30s)

==> Toggling health → DOWN
    Container Apps liveness probe checks /actuator/health periodically.
    On probe failure the replica is restarted — new replica starts healthy.
    Watch: Azure Portal → Monitor → Alerts → tf-public-cloud-app-5xx-alert
           Container Apps → tf-public-cloud-app → Metrics → Requests by status
{"status": "DOWN"}

==> Phase 2: waiting for platform to replace the instance (no manual toggle)
    503 = app reporting DOWN

[17:00:36] GET    /api/items                     → 503
[17:00:37] GET    /api/items/1                   → 503
... (503s while probe detects failure and replica restarts — ~30-60s)
[17:01:22] GET    /api/items                     → 200
[17:01:22] GET    /api/items/1                   → 200
[17:01:23] GET    /actuator/health               → 200
[17:01:23] GET    /actuator/health               → 200
[17:01:24] GET    /actuator/health               → 200

==> Recovery confirmed — Container Apps restarted the replica, new instance is healthy
    Time from toggle to recovery: 62s

==> Phase 3: post-recovery traffic for 30s — confirming stable 200s
[17:01:25] GET    /api/items                     → 200
...

==> Fetching logs around the replacement window
2026-06-18T17:00:35.123Z Health toggled to DOWN
2026-06-18T17:00:36.001Z GET /actuator/health → 503
2026-06-18T17:01:20.441Z Started Application in 1.731 seconds
2026-06-18T17:01:22.003Z GET /actuator/health → 200

==> Demo complete
    Look for the Spring Boot startup banner — that is the new instance.
    The timestamp gap around the toggle confirms the old instance was restarted.

=== Summary ===
  Total requests : 241
  2xx             : 198
  4xx             : 18
  5xx (503)       : 25
  502 (no target) : 0
```
