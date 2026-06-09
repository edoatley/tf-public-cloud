variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for the bucket."
  type        = string
  default     = "europe-west2"
}

variable "bucket_name" {
  description = "Globally unique name for the GCS bucket (a random suffix is appended)."
  type        = string
  default     = "tf-public-cloud-object-storage"
}

variable "kms_key_name" {
  description = "Resource name of a Cloud KMS key for CMEK encryption. Leave null to use Google-managed encryption."
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels applied to the bucket."
  type        = map(string)
  default     = {}
}
