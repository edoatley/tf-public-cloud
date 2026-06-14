variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for Cloud Run (must be a Cloud Run-supported region)."
  type        = string
  default     = "europe-west1"
}

variable "image_tag" {
  description = "Docker image tag to deploy."
  type        = string
  default     = "latest"
}

variable "service_name" {
  description = "Cloud Run service name and Docker image name within the registry."
  type        = string
  default     = "tf-public-cloud-app"
}
