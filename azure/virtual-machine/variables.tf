variable "subscription_id" {
  description = "Azure subscription ID. Injected via TF_VAR_subscription_id in CI."
  type        = string
}

variable "resource_group_name" {
  description = "Base name for the resource group. A random hex suffix is appended."
  type        = string
  default     = "rg-tf-public-cloud-vm"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "uksouth"
}

variable "name_prefix" {
  description = "Short prefix for resource names. A random hex suffix is appended."
  type        = string
  default     = "tfpubcloudvm"
}

variable "vm_size" {
  description = "Azure VM size."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_username" {
  description = "SSH admin username on the VM."
  type        = string
  default     = "azureuser"
}

variable "address_space" {
  description = "Address space for the virtual network."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_prefix" {
  description = "Address prefix for the subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "ssh_public_key_b64" {
  description = "Base64-encoded OpenSSH public key to install on the VM. Injected via TF_VAR_ssh_public_key_b64 in CI."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
