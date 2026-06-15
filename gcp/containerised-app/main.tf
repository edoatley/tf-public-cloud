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

resource "google_monitoring_alert_policy" "run_5xx" {
  display_name = "tf-public-cloud-app Cloud Run 5xx errors"
  combiner     = "OR"

  conditions {
    display_name = "5xx response count > 0"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"cloud_run_revision\"",
        "metric.type = \"run.googleapis.com/request_count\"",
        "metric.labels.response_code_class = \"5xx\"",
        "resource.labels.service_name = \"${var.service_name}\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "60s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }
}
