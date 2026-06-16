output "function_url" {
  description = "HTTPS endpoint for the Lambda function."
  value       = aws_lambda_function_url.this.function_url
}

output "function_name" {
  description = "Lambda function name."
  value       = aws_lambda_function.this.function_name
}
