output "function_url" {
  description = "HTTPS endpoint for the Cloud Function."
  value       = google_cloudfunctions2_function.this.service_config[0].uri
}

output "function_name" {
  description = "Cloud Function name."
  value       = google_cloudfunctions2_function.this.name
}
