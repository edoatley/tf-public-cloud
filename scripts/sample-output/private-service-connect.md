# Private Service Connect — Sample Output

## GCP (Compute Engine + internal passthrough NLB + service attachment)

Captured from `release-1.1.3`, applied to `europe-west2` / `europe-west2-b`. The random suffix
on every resource name is `9b3f`.

Addresses allocated on this run:

| | Address | Subnetwork |
|---|---|---|
| Producer VM | `10.10.0.2` | producer `10.10.0.0/24` |
| PSC source NAT | `10.10.100.2` | PSC NAT `10.10.100.0/24` |
| PSC endpoint | `10.20.0.2` | consumer `10.20.0.0/24` |
| Consumer VM | `10.20.0.3` | consumer `10.20.0.0/24` |

```
$ ./scripts/examples/private-service-connect/gcp.sh

==> Discovering resources matching 'tf-public-cloud-psc'
    producer VM   : tf-public-cloud-psc-producer-9b3f (10.10.0.2) in tf-public-cloud-psc-producer-vpc-9b3f
    consumer VM   : tf-public-cloud-psc-consumer-9b3f (10.20.0.3) in tf-public-cloud-psc-consumer-vpc-9b3f
    PSC endpoint  : 10.20.0.2 (inside the consumer subnetwork)
    attachment    : tf-public-cloud-psc-attachment-9b3f (europe-west2)
    PSC NAT range : 10.10.100.0/24

==> 1. Producer reports the consumer endpoint as ACCEPTED
  PASS  connection status is ACCEPTED

==> 2. Consumer reached the service on boot (serial console, no SSH needed)
  PASS  PSC-TEST: 200 from 10.20.0.2
    PSC-BODY: <html><body><h1>PSC producer</h1><p>Served by tf-public-cloud-psc-producer-9b3f</p></body></html>

==> 3. Producer saw the request arrive source-NATed from 10.10.100.0/24
  PASS  access log shows: 10.10.100.2 - - [27/Sep/2026 12:34:16] "GET / HTTP/1.1" 200 -
  PASS  producer never saw the consumer's own address (10.20.0.3)

==> 4. No VPC peering exists between the two networks
  PASS  producer network tf-public-cloud-psc-producer-vpc-9b3f has no peerings

==> 5. Consumer has no route into the producer VPC (needs IAP SSH)
    10.10.0.2 via 10.20.0.1 dev ens4 src 10.20.0.3 uid 1000
    cache
  PASS  producer address resolves via the default gateway, not a VPC route

==> 6. Live request from the consumer over the PSC endpoint (needs IAP SSH)
    <html><body><h1>PSC producer</h1><p>Served by tf-public-cloud-psc-producer-9b3f</p></body></html>
  PASS  HTTP 200 from 10.20.0.2 on demand

=== Summary ===
  passed  : 7
  skipped : 0
  failed  : 0

Private Service Connect verified.
  tf-public-cloud-psc-consumer-9b3f has no public IP, no peering and no route to tf-public-cloud-psc-producer-vpc-9b3f,
  yet gets HTTP 200 from 10.20.0.2 — an address in its own subnetwork.
```

### Reading the output

Checks 2 and 3 are the pair that matter. The consumer called `10.20.0.2`, an address in its
**own** subnetwork, and got the producer's page back. The producer logged that same request
arriving from `10.10.100.2` — an address in the PSC NAT subnetwork — and never saw `10.20.0.3`,
the consumer VM's real address. That translation is what lets a producer serve consumers whose
address space it knows nothing about, and it is why the producer's firewall rule must permit
`psc_nat_cidr` rather than `consumer_cidr`.

Check 5 is the negative case. `ip route get 10.10.0.2` from inside the consumer resolves
`via 10.20.0.1` — the consumer subnet's default gateway — rather than through any route into the
producer VPC, because no such route exists. The consumer can reach the *service* and cannot reach
the *network* hosting it.

On the first run, `gcloud compute ssh` generates `~/.ssh/google_compute_engine` before checks 5
and 6 can connect; that one-time key generation has been omitted here.

### Independent confirmation from GCP

Network Intelligence Center Connectivity Tests, run against the same deployment, traces the path
itself. Forward, to the PSC endpoint:

```
VM instance
  -> Default egress firewall rule
  -> Subnet route
  -> Forwarding rule                      (the PSC endpoint)
  -> NAT (Private Service Connect)        (src 10.20.0.3 becomes 10.10.100.2)
  -> Forwarding rule                      (the producer ILB)
  -> Load balancer backend analysis
  -> VM instance
  -> Ingress firewall rule
  -> Packet could be delivered to tf-public-cloud-psc-producer-9b3f

Overall: Reachable.  Live data plane: 50/50 packets delivered, 0.05 ms median.
```

The return trace runs the same hops in reverse with the NAT undone, and is also Reachable.

To the producer VM directly, in the same project and region:

```
VM instance
  -> Default egress firewall rule         (default-allow-egress, implied)
  -> Subnet route                         (0.0.0.0/0, NEXT_HOP_INTERNET_GATEWAY)
  -> DROP                                 cause: PRIVATE_TRAFFIC_TO_INTERNET

Overall: Unreachable.
```

No peering hop appears in either trace, and no route covering `10.10.0.0/24` exists in the
consumer VPC. For packet B the only matching route is the default one, so the packet is handed
to the internet gateway and dropped there for carrying an RFC1918 destination.

### First deployment took four attempts

Worth recording, since none of these were catchable by `terraform validate`, `tflint` or
`terraform plan` — all three are properties of the live environment rather than the
configuration:

| Attempt | Failure | Fix |
|---|---|---|
| `release-1.1.0` | `europe-west2-a` had no capacity for `e2-micro` | Moved the zone default to `europe-west2-b` |
| `release-1.1.1` | `Balancing mode must be CONNECTION for an INTERNAL backend service` | Set `balancing_mode = "CONNECTION"` on the backend |
| `release-1.1.2` | `servicedirectory.namespaces.create` denied on `goog-psc-default` | Added `roles/servicedirectory.editor` and enabled the API |
| `release-1.1.3` | — | 18/18 applied, 7/7 checks passed |
