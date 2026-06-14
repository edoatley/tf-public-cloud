resource "google_artifact_registry_repository" "this" {
  location      = var.region
  repository_id = var.repository_id
  description   = var.description
  format        = "DOCKER"
}

resource "google_artifact_registry_repository_iam_member" "ci_writer" {
  location   = google_artifact_registry_repository.this.location
  repository = google_artifact_registry_repository.this.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.ci_service_account}"
}
