# Private Service Connect

- [Private Service Connect](#private-service-connect)
  - [Introduction](#introduction)
    - [What the example provisions](#what-the-example-provisions)
  - [Concepts and terminology](#concepts-and-terminology)
    - [Three different things are called PSC](#three-different-things-are-called-psc)
    - [Why a load balancer is mandatory](#why-a-load-balancer-is-mandatory)
    - [The NAT subnetwork](#the-nat-subnetwork)
  - [GCP — Private Service Connect](#gcp--private-service-connect)
    - [`gcp/private-service-connect`](#gcpprivate-service-connect)
    - [Key design decisions](#key-design-decisions)
  - [Deploying](#deploying)
    - [Via GitHub Actions (recommended)](#via-github-actions-recommended)
    - [Locally](#locally)
  - [Verifying](#verifying)
    - [What the script checks](#what-the-script-checks)
    - [Doing it by hand](#doing-it-by-hand)
  - [Cleaning up](#cleaning-up)
  - [Other clouds](#other-clouds)

## Introduction

Private Service Connect (PSC) lets a service in one VPC be consumed from another VPC without
joining the two networks. No peering, no VPN, no shared route table, no overlapping-CIDR
negotiation, and no public IP on either side. The consumer reaches the service at an ordinary
internal address inside its *own* subnetwork.

This example builds **both halves** — the producer that publishes a service and the consumer that
connects to it — so the mechanism is visible rather than hidden behind a Google-managed service.

![Private Service Connect architecture](images/private-service-connect.drawio.png)

*Every IP range in the diagram belongs to a subnetwork, not to a network — GCP VPCs have no CIDR
of their own. The purple path is the only route between the two VPCs, and it is one-way. Note
what the producer sees at the far right: traffic arrives from `10.10.100.x`, never from the
consumer's own `10.20.0.x`, which is why the producer firewall must permit the NAT range.*

### What the example provisions

|                       | Producer VPC                                              | Consumer VPC                                     |
| --------------------- | --------------------------------------------------------- | ------------------------------------------------ |
| **Module path**       | `gcp/private-service-connect` (one root module, both VPCs) |                                                  |
| **Network**           | `…-producer-vpc-<hex>`, `auto_create_subnetworks = false` | `…-consumer-vpc-<hex>`                           |
| **Subnetworks**       | backend `10.10.0.0/24` + PSC NAT `10.10.100.0/24`         | `10.20.0.0/24`                                   |
| **Workload**          | `e2-micro` serving a static page on port 80               | `e2-micro` that curls the endpoint on boot       |
| **Load balancer**     | Regional internal passthrough NLB (L4, TCP:80)            | —                                                |
| **PSC resource**      | `google_compute_service_attachment`                       | `google_compute_forwarding_rule` (the endpoint)  |
| **Public IPs**        | None                                                      | None                                             |
| **Ingress rules**     | Health-check ranges + the PSC NAT range, both on TCP:80   | IAP TCP forwarding range on TCP:22               |
| **Resource count**    | 11                                                        | 6 (+1 `random_id`)                               |

## Concepts and terminology

### Three different things are called PSC

| Flavour                              | What it connects to                                | Built here |
| ------------------------------------ | -------------------------------------------------- | ---------- |
| PSC endpoint to Google APIs          | `storage.googleapis.com` and friends, privately    | No         |
| PSC endpoint to a Google-managed service | Cloud SQL, Memorystore, a partner service      | No         |
| **Published service**                | **A service you run, in a VPC you own**            | **Yes**    |

Only the third has a producer side you write yourself. The first two are easier to stand up but
Google owns the half that makes PSC interesting, so nothing about the mechanism is observable.

### Why a load balancer is mandatory

A service attachment can only target an **internal load balancer's forwarding rule**. It cannot
target an instance, an instance group, or an address. This is the single biggest reason a minimal
PSC demo is not three resources: a health check, a backend service and a forwarding rule all have
to exist before there is anything to publish.

This example uses a regional internal *passthrough* Network Load Balancer (L4). A regional
internal Application Load Balancer also works and gives you L7 routing, but it additionally
requires a proxy-only subnetwork.

### The NAT subnetwork

The producer needs a subnetwork with `purpose = "PRIVATE_SERVICE_CONNECT"`. It holds no
instances and takes no `role`. PSC source-NATs every consumer connection into this range before
it reaches the backend.

That translation is what makes PSC scale to consumers whose address space the producer knows
nothing about — including consumers whose ranges overlap each other, or overlap the producer's.
It also has two consequences worth internalising:

- **Producer firewall rules must permit the NAT range, not the consumer's range.** Permitting the
  consumer subnetwork instead produces a connection that reaches `ACCEPTED` at the control plane
  and times out at the data plane — a failure that looks like success from the Terraform output.
- **The producer never learns the client's real address.** Use the PSC connection ID for
  attribution instead.

## GCP — Private Service Connect

### `gcp/private-service-connect`

**Required variables:**

- `project` — GCP project ID. CI injects this as `-var="project=…"`.

**Optional variables (all have defaults):**

- `region` — default `europe-west2`. Both VPCs, the load balancer and the endpoint must share one region.
- `zone` — default `europe-west2-b`. Only the instances and instance group are zonal, so a stockout in one zone is a one-line change that recreates nothing regional.
- `name_prefix` — default `tf-public-cloud-psc`. A random hex suffix is appended.
- `machine_type` — default `e2-micro` for both instances.
- `producer_cidr` — default `10.10.0.0/24`.
- `psc_nat_cidr` — default `10.10.100.0/24`.
- `consumer_cidr` — default `10.20.0.0/24`.
- `labels` — default `{}`, applied to both instances.

### Key design decisions

- **One project, two VPCs.** VPCs in a single project share nothing by default, so every property
  PSC provides is still demonstrated without the bootstrap, billing and IAM cost of a second
  project. The one thing this cannot show is a meaningful `ACCEPT_MANUAL` allow list, so the
  attachment uses `ACCEPT_AUTOMATIC`.
- **`python3 -m http.server` rather than nginx.** Debian 12 ships python3, so the producer needs
  no outbound internet access — and therefore no Cloud Router, no Cloud NAT and no public IP.
  `apt-get install nginx` would require all three, tripling the networking footprint of a module
  whose subject *is* networking.
- **`load_balancing_scheme = ""` on the consumer forwarding rule.** The empty string is what makes
  it a PSC endpoint rather than a load balancer. Any other value silently changes what you built.
  `ip_address` must also be the address resource's `id`, not its `.address` attribute.
- **No public IPs anywhere, and SSH only via IAP TCP forwarding** (`35.235.240.0/20`). A demo of
  private connectivity that reaches its test host over the internet would undercut its own point.
- **The consumer tests itself on boot.** A startup script curls the endpoint and writes one
  grep-able `PSC-TEST:` line to the serial console. This is the primary proof because it needs no
  SSH, no IAP role and no extra API — just `compute.instances.getSerialPortOutput`.
- **The producer's access log is mirrored to the serial console** (`StandardError=journal+console`
  on the systemd unit). That is how the demo proves source NAT without opening an SSH path into
  the producer VPC. Deliberately noisy; do not copy this into production.
- **No IAM changes needed.** `roles/compute.admin`, already granted in
  `scripts/iam/gcp-permissions.json`, covers networks, subnetworks, firewalls, addresses,
  instances, instance groups, health checks, backend services, forwarding rules and service
  attachments.

## Deploying

### Via GitHub Actions (recommended)

Plan uses read-only credentials and the `default` environment, so it runs from any branch:

```sh
gh workflow run plan-resource.yml \
  --field resource_type=private-service-connect --field cloud=gcp --ref <branch>
gh run watch
```

Apply and destroy use the `production` environment, which permits only refs matching
`release-*` and requires reviewer approval. Tag first, then dispatch against the tag:

```sh
git tag release-1.0.7
git push origin release-1.0.7

gh workflow run apply-resource.yml --ref release-1.0.7 \
  --field resource_type=private-service-connect --field cloud=gcp --field action=apply
```

See [docs/GitHub.md](GitHub.md) for the environment protection rules.

### Locally

```sh
cd gcp/private-service-connect
terraform init
terraform plan  -var="project=$(gcloud config get-value project)"
terraform apply -var="project=$(gcloud config get-value project)"
```

Expect 18 resources. The consumer instance's boot-time check retries for up to five minutes, so
allow a couple of minutes after apply before verifying — the backend has to pass its health check
first.

## Verifying

```sh
./scripts/examples/private-service-connect/gcp.sh
```

The script discovers everything by name via `gcloud`, so it needs no Terraform state access. It
exits non-zero if any hard assertion fails.

### What the script checks

| # | Check                                                            | Hard assertion | Needs IAP SSH |
| - | ---------------------------------------------------------------- | -------------- | ------------- |
| 1 | Producer reports the consumer endpoint as `ACCEPTED`             | Yes            | No            |
| 2 | Consumer got HTTP 200 on boot (`PSC-TEST: 200` on serial console) | Yes           | No            |
| 3 | Producer's access log shows a source address in the NAT range, and never the consumer's own address | Yes | No |
| 4 | Neither network has any VPC peering                              | Yes            | No            |
| 5 | Consumer has no route into the producer VPC                      | No — skips     | Yes           |
| 6 | Live on-demand `curl` through the endpoint                       | No — skips     | Yes           |

Checks 5 and 6 need `roles/iap.tunnelResourceAccessor` on the caller and may need
`gcloud services enable iap.googleapis.com`. They are deliberately not load-bearing: checks 1–4
already prove the data path and the absence of any network join.

### Doing it by hand

```sh
cd gcp/private-service-connect
eval "$(terraform output -raw verify_command)"          # the boot-time result
terraform output psc_endpoint_ip                        # an address in the CONSUMER subnetwork
terraform output producer_instance_ip                   # an address the consumer cannot route to

# The producer's view of the client: a PSC NAT address, not the consumer VM
gcloud compute instances get-serial-port-output "$(terraform output -raw producer_instance_name)" \
  --zone europe-west2-b | grep 'GET / HTTP'

# What is NOT there
gcloud compute networks describe "$(terraform output -raw producer_network_name)" \
  --format='value(peerings[].name)'                     # empty

# Poke around from inside the consumer
gcloud compute ssh "$(terraform output -raw consumer_instance_name)" \
  --zone europe-west2-b --tunnel-through-iap
consumer$ curl "$(…psc_endpoint_ip)"                    # 200
consumer$ ip route get <producer_instance_ip>           # via the default gateway, no VPC route
consumer$ curl -m 5 <producer_instance_ip>              # times out — no path to the producer
```

The last two lines are the point of the whole module: the consumer can reach the *service* and
cannot reach the *network* hosting it.

## Cleaning up

```sh
gh workflow run apply-resource.yml --ref release-1.0.7 \
  --field resource_type=private-service-connect --field cloud=gcp --field action=destroy
```

PSC endpoints bill per hour on top of the two `e2-micro` instances and the internal forwarding
rule, so do not leave this applied.

## Other clouds

The AWS and Azure analogues — PrivateLink endpoint services, and Private Link Service behind a
Standard Load Balancer — are **not built in this repo**. This example is GCP-only, so nothing
here should be read as a three-way comparison.
