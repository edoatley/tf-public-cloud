variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-2"
}

variable "repository_name" {
  description = "ECR repository name."
  type        = string
  default     = "tf-public-cloud-app"
}

variable "tags" {
  description = "Tags applied to all resources via provider default_tags."
  type        = map(string)
  default     = {}
}
