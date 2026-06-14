output "repository_url" {
  description = "Full ECR repository URL (used as image base in containerised-app)."
  value       = aws_ecr_repository.this.repository_url
}

output "registry_id" {
  description = "ECR registry ID (AWS account ID)."
  value       = aws_ecr_repository.this.registry_id
}

output "repository_name" {
  description = "ECR repository name."
  value       = aws_ecr_repository.this.name
}
