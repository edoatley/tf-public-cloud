variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for the Artifact Registry repository."
  type        = string
  default     = "europe-west2"
}

variable "repository_id" {
  description = "Artifact Registry repository ID."
  type        = string
  default     = "tf-public-cloud-app"
}

variable "description" {
  description = "Human-readable description for the repository."
  type        = string
  default     = "Docker images for the tf-public-cloud containerised app"
}

variable "ci_service_account" {
  description = "Service account email that CI uses to push images. Granted artifactregistry.writer."
  type        = string
}
