resource "random_id" "suffix" {
  byte_length = 2
}

data "google_compute_image" "debian_12" {
  family  = "debian-12"
  project = "debian-cloud"
}

resource "google_compute_network" "this" {
  name                    = "${var.name_prefix}-vpc-${random_id.suffix.hex}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "public" {
  name          = "${var.name_prefix}-subnet-${random_id.suffix.hex}"
  ip_cidr_range = var.network_cidr
  region        = var.region
  network       = google_compute_network.this.id
}

resource "google_compute_firewall" "ssh" {
  name    = "${var.name_prefix}-allow-ssh-${random_id.suffix.hex}"
  network = google_compute_network.this.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh-enabled"]
}

resource "google_compute_address" "this" {
  name   = "${var.name_prefix}-ip-${random_id.suffix.hex}"
  region = var.region
}

resource "google_compute_instance" "this" {
  name         = "${var.name_prefix}-${random_id.suffix.hex}"
  machine_type = var.machine_type
  zone         = var.zone

  tags   = ["ssh-enabled"]
  labels = var.labels

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_12.self_link
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id

    access_config {
      nat_ip = google_compute_address.this.address
    }
  }

  metadata = {
    ssh-keys = "debian:${var.ssh_public_key}"
  }
}
