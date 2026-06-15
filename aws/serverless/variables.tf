variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-2"
}

variable "function_name" {
  description = "Name for the Lambda function and associated IAM role."
  type        = string
  default     = "tf-public-cloud-add"
}

variable "tags" {
  description = "Tags applied to all resources via provider default_tags."
  type        = map(string)
  default     = {}
}
