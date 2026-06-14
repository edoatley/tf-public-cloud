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
  description = "Name for the resource group."
  type        = string
  default     = "rg-tf-public-cloud-acr"
}

variable "registry_name" {
  description = "ACR name — must be globally unique, alphanumeric only, 5-50 chars."
  type        = string
  default     = "tfpubcloudacredoatley"
}

variable "sku" {
  description = "ACR SKU — Basic, Standard, or Premium."
  type        = string
  default     = "Basic"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
