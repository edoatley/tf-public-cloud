# Containerised App (ECS Fargate, prod) — Sample Output

## AWS

```
$ ./scripts/examples/containerised-app-prod/aws.sh

=== 1. ALB lookup ===
  ALB DNS : tf-public-cloud-app-prod-alb-1696508157.eu-west-2.elb.amazonaws.com
  TLS host: fargate-test.edoatley.co.uk

=== 2. Health check ===
  PASS: health endpoint returned UP

=== 3. Items API smoke test ===
  PASS: GET /api/items returned 3 items
  PASS: GET /api/items/1 returned item: Widget

=== 4. Load test: 5 TPS for 30s ===
  Total requests : 65
  HTTP 200       : 65
  Other          : 0
  PASS: all 65 requests returned 200

=== 5. Force 404 ===
  PASS: GET /api/items/99999 correctly returned 404

=== 6. AZ failover + autoscaling ===
--- 6a. Stopping one task (AZ failover) ---
  Stopping task in eu-west-2a: 02d44a273d70454aa6580ce648e5ee76
  --------------------------------
  |           StopTask           |
  +-------------+----------------+
  |     az      |  lastStatus    |
  +-------------+----------------+
  |  eu-west-2a |  DEACTIVATING  |
  +-------------+----------------+
  Waiting 20s for ALB to drain stopped task...
  PASS: traffic still served after task stop (AZ failover confirmed)
  -----------------------------------
  |        DescribeServices         |
  +---------+-----------+-----------+
  | desired |  pending  |  running  |
  +---------+-----------+-----------+
  |  2      |  0        |  1        |
  +---------+-----------+-----------+

--- 6b. Driving load to trigger autoscale (cpu_scale_target=5%) ---
  Sending sustained load for 180s (monitoring CPU every 20s)...
  running=1  cpu=1.277756998936335%
  running=1  cpu=6.018153389294943%
  running=2  cpu=6.018153389294943%
  running=2  cpu=10.174220813645256%
  running=2  cpu=31.245236459705566%
  PASS: ECS scaled out to 2 tasks under load

--- 6c. Final service state ---
  -----------------------------------
  |        DescribeServices         |
  +---------+-----------+-----------+
  | desired |  pending  |  running  |
  +---------+-----------+-----------+
  |  2      |  0        |  2        |
  +---------+-----------+-----------+

=== 7. Recent CloudWatch logs (last 10 min) ===
2026-06-22T12:24:35Z  10.1.1.137 - - [22/Jun/2026:12:24:35 +0000] "GET /api/items HTTP/1.1" 200 227 200982
2026-06-22T12:24:35Z  10.1.1.137 - - [22/Jun/2026:12:24:35 +0000] "GET /api/items HTTP/1.1" 200 227 200823
2026-06-22T12:24:35Z  127.0.0.1 - - [22/Jun/2026:12:24:35 +0000] "GET /actuator/health HTTP/1.1" 200 25 1878
2026-06-22T12:24:36Z  10.1.1.137 - - [22/Jun/2026:12:24:36 +0000] "GET /api/items HTTP/1.1" 200 227 201617
2026-06-22T12:24:37Z  10.1.2.128 - - [22/Jun/2026:12:24:37 +0000] "GET /actuator/health HTTP/1.1" 200 25 2602
2026-06-22T12:24:37Z  10.1.1.137 - - [22/Jun/2026:12:24:37 +0000] "GET /actuator/health HTTP/1.1" 200 25 8043

=== 8. ECS service state ===
---------------------------------------------
|             DescribeServices              |
+---------+-----------+-----------+---------+
| desired |  pending  |  running  | status  |
+---------+-----------+-----------+---------+
|  2      |  1        |  2        |  ACTIVE |
+---------+-----------+-----------+---------+

=== Summary ===
  Passed : 7
  Failed : 0

All 7 checks passed.
```

### Access log format

Each request line in CloudWatch follows the Tomcat combined log format:

```
<client-ip> - - [<timestamp>] "<method> <path> <protocol>" <status> <bytes> <duration-ms>
```

- `10.1.x.x` — ALB node IP (private subnet)
- `127.0.0.1` — ECS container health check (in-container wget)
- Final field — response time in **microseconds** (200,000µs ≈ 200ms artificial delay on `/api/items`)
- `/actuator/health` responses are undelayed (~2ms)
