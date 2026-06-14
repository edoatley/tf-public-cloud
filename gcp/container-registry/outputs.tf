output "repository_url" {
  description = "Artifact Registry base URL for Docker images (append /{image_name}:{tag})."
  value       = "${var.region}-docker.pkg.dev/${var.project}/${var.repository_id}"
}

output "repository_id" {
  description = "Artifact Registry repository ID."
  value       = google_artifact_registry_repository.this.repository_id
}
