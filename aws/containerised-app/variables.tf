variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-2"
}

variable "image_tag" {
  description = "Docker image tag to deploy."
  type        = string
  default     = "latest"
}

variable "cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 512
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.1.0.0/16"
}

variable "subnet_cidr_a" {
  description = "CIDR for the first public subnet (AZ a)."
  type        = string
  default     = "10.1.1.0/24"
}

variable "subnet_cidr_b" {
  description = "CIDR for the second public subnet (AZ b) — required by ALB."
  type        = string
  default     = "10.1.2.0/24"
}

variable "tags" {
  description = "Tags applied to all resources via provider default_tags."
  type        = map(string)
  default     = {}
}
