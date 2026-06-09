variable "bucket_name" {
  description = "Globally unique name for the S3 bucket (a random suffix is appended)."
  type        = string
  default     = "tf-public-cloud-object-storage"
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-2"
}

variable "enable_kms" {
  description = "Use KMS-managed encryption (SSE-KMS) instead of S3-managed (SSE-S3)."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key to use when enable_kms is true."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources via the provider default_tags block."
  type        = map(string)
  default     = {}
}
