resource "random_id" "suffix" {
  byte_length = 2
}

resource "google_storage_bucket" "this" {
  name     = "${var.bucket_name}-${random_id.suffix.hex}"
  project  = var.project
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  dynamic "encryption" {
    for_each = var.kms_key_name != null ? [var.kms_key_name] : []
    content {
      default_kms_key_name = encryption.value
    }
  }

  labels = var.labels

  force_destroy = false
}
