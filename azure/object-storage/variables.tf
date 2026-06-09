variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group to create (a random suffix is appended)."
  type        = string
  default     = "rg-tf-public-cloud-object-storage"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "uksouth"
}

variable "storage_account_name" {
  description = "Name of the storage account (3-24 lowercase alphanumeric, globally unique; a random suffix is appended)."
  type        = string
  default     = "tfpubcloudobjectstor"
}

variable "container_name" {
  description = "Name of the blob container."
  type        = string
  default     = "data"
}

variable "account_replication_type" {
  description = "Storage replication type (LRS, GRS, ZRS, GZRS, etc.)."
  type        = string
  default     = "LRS"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
