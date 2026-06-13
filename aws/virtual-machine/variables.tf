variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-2"
}

variable "name_prefix" {
  description = "Prefix for all resource names. A random hex suffix is appended for uniqueness."
  type        = string
  default     = "tf-public-cloud-vm"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "ssh_public_key" {
  description = "OpenSSH public key to install on the instance. Injected via TF_VAR_ssh_public_key in CI."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags applied to all resources via the provider default_tags block."
  type        = map(string)
  default     = {}
}
