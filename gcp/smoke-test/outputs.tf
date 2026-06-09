output "project_id" {
  description = "GCP project ID seen by the runner."
  value       = data.google_project.current.project_id
}

output "project_number" {
  description = "GCP project number."
  value       = data.google_project.current.number
}

output "caller_email" {
  description = "Email of the identity used by the runner."
  value       = data.google_client_openid_userinfo.current.email
}
