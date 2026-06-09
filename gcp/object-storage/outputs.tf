output "bucket_name" {
  description = "Name of the GCS bucket."
  value       = google_storage_bucket.this.name
}

output "bucket_url" {
  description = "gs:// URL of the bucket."
  value       = google_storage_bucket.this.url
}

output "bucket_self_link" {
  description = "Self-link URI of the bucket."
  value       = google_storage_bucket.this.self_link
}
