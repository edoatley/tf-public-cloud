data "terraform_remote_state" "registry" {
  backend = "gcs"
  config = {
    bucket = "tf-public-cloud-gcp-state-edo"
    prefix = "gcp/container-registry"
  }
}

locals {
  # repository_url is the base path; image name is appended as a sub-path
  image_uri = "${data.terraform_remote_state.registry.outputs.repository_url}/${var.service_name}:${var.image_tag}"
}

resource "google_cloud_run_v2_service" "this" {
  name                = var.service_name
  location            = var.region
  deletion_protection = false

  template {
    containers {
      image = local.image_uri

      ports {
        container_port = 8080
      }

      liveness_probe {
        http_get {
          path = "/actuator/health"
          port = 8080
        }
        initial_delay_seconds = 30
        period_seconds        = 10
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  location = google_cloud_run_v2_service.this.location
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
