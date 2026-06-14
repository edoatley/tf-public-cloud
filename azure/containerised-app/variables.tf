variable "subscription_id" {
  description = "Azure subscription ID. Injected via TF_VAR_subscription_id in CI."
  type        = string
  sensitive   = true
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "uksouth"
}

variable "resource_group_name" {
  description = "Base name for the resource group (random suffix appended)."
  type        = string
  default     = "rg-tf-public-cloud-app"
}

variable "image_tag" {
  description = "Docker image tag to deploy."
  type        = string
  default     = "latest"
}

variable "app_name" {
  description = "Container App name and Docker image name within the registry."
  type        = string
  default     = "tf-public-cloud-app"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
