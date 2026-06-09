output "account_id" {
  description = "AWS account ID seen by the runner."
  value       = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  description = "ARN of the IAM identity used by the runner."
  value       = data.aws_caller_identity.current.arn
}

output "region" {
  description = "AWS region the provider is configured for."
  value       = data.aws_region.current.name
}

output "partition" {
  description = "AWS partition (aws, aws-cn, aws-us-gov)."
  value       = data.aws_partition.current.partition
}
