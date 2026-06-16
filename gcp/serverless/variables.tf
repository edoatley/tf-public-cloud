variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for Cloud Functions v2."
  type        = string
  default     = "europe-west1"
}

variable "function_name" {
  description = "Name for the Cloud Function."
  type        = string
  default     = "tf-public-cloud-add"
}

variable "source_bucket" {
  description = "GCS bucket used to stage the function zip. Defaults to the Terraform state bucket which already exists."
  type        = string
  default     = "tf-public-cloud-gcp-state-edo"
}
