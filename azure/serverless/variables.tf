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
  default     = "rg-tf-public-cloud-serverless"
}

variable "function_app_name" {
  description = "Base name for the Function App (random suffix appended for global uniqueness)."
  type        = string
  default     = "tfpubcloudfn"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
