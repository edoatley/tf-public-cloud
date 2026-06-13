variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region to deploy into."
  type        = string
  default     = "europe-west2"
}

variable "zone" {
  description = "GCP zone for the Compute Engine instance."
  type        = string
  default     = "europe-west2-a"
}

variable "name_prefix" {
  description = "Prefix for all resource names. A random hex suffix is appended for uniqueness."
  type        = string
  default     = "tf-public-cloud-vm"
}

variable "machine_type" {
  description = "Compute Engine machine type."
  type        = string
  default     = "e2-micro"
}

variable "network_cidr" {
  description = "CIDR range for the subnetwork."
  type        = string
  default     = "10.0.0.0/16"
}

variable "ssh_public_key" {
  description = "OpenSSH public key to install on the instance. Injected via TF_VAR_ssh_public_key in CI."
  type        = string
  sensitive   = true
}

variable "labels" {
  description = "Labels applied to all resources."
  type        = map(string)
  default     = {}
}
