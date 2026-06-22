variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-2"
}

variable "image_tag" {
  description = "Docker image tag to deploy. Must match a tag pushed to ECR (commit SHA)."
  type        = string
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

variable "subnet_cidr_public_a" {
  description = "CIDR for the first public subnet (AZ a) — hosts the ALB and NAT Gateway."
  type        = string
  default     = "10.1.1.0/24"
}

variable "subnet_cidr_public_b" {
  description = "CIDR for the second public subnet (AZ b) — required by ALB."
  type        = string
  default     = "10.1.2.0/24"
}

variable "subnet_cidr_private_a" {
  description = "CIDR for the first private subnet (AZ a) — hosts ECS tasks."
  type        = string
  default     = "10.1.10.0/24"
}

variable "subnet_cidr_private_b" {
  description = "CIDR for the second private subnet (AZ b) — hosts ECS tasks."
  type        = string
  default     = "10.1.11.0/24"
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks for auto-scaling."
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks for auto-scaling."
  type        = number
  default     = 4
}

variable "cpu_scale_target" {
  description = "Target CPU utilisation percentage for ECS auto-scaling."
  type        = number
  default     = 5
}

variable "enable_https" {
  description = "Enable HTTPS listener on the ALB. Requires domain_name and route53_zone_id."
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Fully-qualified domain name for the ACM certificate and Route53 A record."
  type        = string
  default     = "fargate-test.edoatley.co.uk"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID in which to create ACM validation and A records."
  type        = string
  default     = "Z08071841XW6QGVOS5UD9"
}

variable "response_delay_ms" {
  description = "Artificial delay in milliseconds added to GET /api/items responses. 0 disables the delay."
  type        = number
  default     = 200
}

variable "tags" {
  description = "Tags applied to all resources via provider default_tags."
  type        = map(string)
  default     = {}
}
