resource "random_id" "suffix" {
  byte_length = 2
}

data "google_compute_image" "debian_12" {
  family  = "debian-12"
  project = "debian-cloud"
}

# ---------------------------------------------------------------------------
# Producer side: a web server behind an internal passthrough Network Load
# Balancer, published as a PSC service attachment.
#
# The load balancer is not optional scaffolding: a service attachment can only
# target an internal load balancer's forwarding rule, never an instance.
# ---------------------------------------------------------------------------

resource "google_compute_network" "producer" {
  name                    = "${var.name_prefix}-producer-vpc-${random_id.suffix.hex}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "producer" {
  name          = "${var.name_prefix}-producer-subnet-${random_id.suffix.hex}"
  ip_cidr_range = var.producer_cidr
  region        = var.region
  network       = google_compute_network.producer.id
}

# PSC source-NATs every consumer connection into this subnetwork. It holds no
# instances, takes no `role`, and is what lets the producer serve consumers
# whose address ranges it knows nothing about.
resource "google_compute_subnetwork" "psc_nat" {
  name          = "${var.name_prefix}-psc-nat-${random_id.suffix.hex}"
  ip_cidr_range = var.psc_nat_cidr
  region        = var.region
  network       = google_compute_network.producer.id
  purpose       = "PRIVATE_SERVICE_CONNECT"
}

# python3 ships with the Debian image, so the instance needs no outbound
# internet access and therefore no Cloud NAT and no public IP. Installing a
# package here would require all three.
resource "google_compute_instance" "producer" {
  name         = "${var.name_prefix}-producer-${random_id.suffix.hex}"
  machine_type = var.machine_type
  zone         = var.zone

  tags   = ["psc-backend"]
  labels = var.labels

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_12.self_link
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.producer.id
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -euxo pipefail

    mkdir -p /var/www
    printf '<html><body><h1>PSC producer</h1><p>Served by %s</p></body></html>\n' "$(hostname)" >/var/www/index.html

    cat >/etc/systemd/system/psc-demo-web.service <<'UNIT'
    [Unit]
    Description=PSC demo static web server
    After=network-online.target

    [Service]
    WorkingDirectory=/var/www
    ExecStart=/usr/bin/python3 -m http.server 80
    Restart=always
    # python3's http.server logs each request to stderr. Mirroring it to the
    # console puts the access log on serial port 1, where it can be read
    # without SSH — that is how the demo proves consumer traffic arrives
    # source-NATed from the PSC NAT subnetwork. Noisy by design, demo only.
    StandardError=journal+console

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable --now psc-demo-web.service
  EOT
}

resource "google_compute_instance_group" "producer" {
  name      = "${var.name_prefix}-producer-ig-${random_id.suffix.hex}"
  zone      = var.zone
  network   = google_compute_network.producer.id
  instances = [google_compute_instance.producer.self_link]

  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_region_health_check" "producer" {
  name   = "${var.name_prefix}-producer-hc-${random_id.suffix.hex}"
  region = var.region

  http_health_check {
    port = 80
  }
}

resource "google_compute_region_backend_service" "producer" {
  name                  = "${var.name_prefix}-producer-bes-${random_id.suffix.hex}"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_region_health_check.producer.id]

  backend {
    group = google_compute_instance_group.producer.id
  }
}

resource "google_compute_forwarding_rule" "producer" {
  name                  = "${var.name_prefix}-producer-ilb-${random_id.suffix.hex}"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  ip_protocol           = "TCP"
  ports                 = ["80"]
  backend_service       = google_compute_region_backend_service.producer.id
  network               = google_compute_network.producer.id
  subnetwork            = google_compute_subnetwork.producer.id
}

resource "google_compute_service_attachment" "this" {
  name        = "${var.name_prefix}-attachment-${random_id.suffix.hex}"
  region      = var.region
  description = "Publishes the producer VPC web service over Private Service Connect."

  enable_proxy_protocol = false
  connection_preference = "ACCEPT_AUTOMATIC"
  nat_subnets           = [google_compute_subnetwork.psc_nat.id]
  target_service        = google_compute_forwarding_rule.producer.id
}

# Without this the backend is permanently UNHEALTHY and the attachment happily
# accepts connections that go nowhere.
resource "google_compute_firewall" "producer_health_check" {
  name    = "${var.name_prefix}-allow-hc-${random_id.suffix.hex}"
  network = google_compute_network.producer.id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["psc-backend"]
}

# The source range is the NAT subnetwork, NOT var.consumer_cidr. Consumer
# packets arrive translated, so permitting the consumer range instead yields a
# connection that reaches ACCEPTED at the control plane and times out at the
# data plane.
resource "google_compute_firewall" "producer_from_psc" {
  name    = "${var.name_prefix}-allow-psc-${random_id.suffix.hex}"
  network = google_compute_network.producer.id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = [var.psc_nat_cidr]
  target_tags   = ["psc-backend"]
}

# ---------------------------------------------------------------------------
# Consumer side: a separate VPC with a PSC endpoint and a test instance.
#
# Nothing joins these two networks. There is no peering, no VPN, no shared
# route table, and no public IP on either instance. The only path between them
# is the service attachment, and it is one-way: the producer cannot initiate
# anything towards the consumer.
# ---------------------------------------------------------------------------

resource "google_compute_network" "consumer" {
  name                    = "${var.name_prefix}-consumer-vpc-${random_id.suffix.hex}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "consumer" {
  name          = "${var.name_prefix}-consumer-subnet-${random_id.suffix.hex}"
  ip_cidr_range = var.consumer_cidr
  region        = var.region
  network       = google_compute_network.consumer.id
}

# The producer service appears to the consumer as an ordinary address inside
# the consumer's own subnetwork.
resource "google_compute_address" "psc_endpoint" {
  name         = "${var.name_prefix}-endpoint-ip-${random_id.suffix.hex}"
  region       = var.region
  subnetwork   = google_compute_subnetwork.consumer.id
  address_type = "INTERNAL"
}

# load_balancing_scheme MUST be the empty string. Any other value makes this a
# load balancer rather than a PSC endpoint, and ip_address must be the address
# resource's id rather than its .address attribute.
resource "google_compute_forwarding_rule" "consumer" {
  name                  = "${var.name_prefix}-endpoint-${random_id.suffix.hex}"
  region                = var.region
  load_balancing_scheme = ""
  target                = google_compute_service_attachment.this.id
  network               = google_compute_network.consumer.id
  ip_address            = google_compute_address.psc_endpoint.id
}

# Curls the endpoint on boot and writes one grep-able line to the serial
# console, so the data path is proven without needing SSH access.
resource "google_compute_instance" "consumer" {
  name         = "${var.name_prefix}-consumer-${random_id.suffix.hex}"
  machine_type = var.machine_type
  zone         = var.zone

  tags   = ["iap-ssh"]
  labels = var.labels

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_12.self_link
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.consumer.id
  }

  # %%{http_code} escapes Terraform's template directive marker so curl receives
  # a literal %{http_code}.
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -uo pipefail

    ENDPOINT="${google_compute_address.psc_endpoint.address}"
    CODE="000"

    for attempt in $(seq 1 30); do
      CODE="$(curl -s -m 5 -o /tmp/psc-body -w '%%{http_code}' "http://$ENDPOINT/")" || CODE="000"
      if [ "$CODE" = "200" ]; then
        echo "PSC-TEST: $CODE from $ENDPOINT"
        echo "PSC-BODY: $(tr -d '\n' </tmp/psc-body)"
        exit 0
      fi
      sleep 10
    done

    echo "PSC-TEST: FAILED after 30 attempts to http://$ENDPOINT/ (last code $CODE)"
    exit 1
  EOT

  depends_on = [google_compute_forwarding_rule.consumer]
}

resource "google_compute_firewall" "consumer_iap_ssh" {
  name    = "${var.name_prefix}-allow-iap-ssh-${random_id.suffix.hex}"
  network = google_compute_network.consumer.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["iap-ssh"]
}
