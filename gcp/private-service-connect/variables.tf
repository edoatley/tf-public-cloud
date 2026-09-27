variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region to deploy into. Both VPCs, the load balancer and the PSC endpoint must share one region."
  type        = string
  default     = "europe-west2"
}

variable "zone" {
  description = "GCP zone for the producer and consumer Compute Engine instances."
  type        = string
  default     = "europe-west2-a"
}

variable "name_prefix" {
  description = "Prefix for all resource names. A random hex suffix is appended for uniqueness."
  type        = string
  default     = "tf-public-cloud-psc"
}

variable "machine_type" {
  description = "Compute Engine machine type for both instances."
  type        = string
  default     = "e2-micro"
}

variable "producer_cidr" {
  description = "CIDR range for the producer subnetwork, which holds the backend instance and the load balancer."
  type        = string
  default     = "10.10.0.0/24"
}

variable "psc_nat_cidr" {
  description = "CIDR range for the producer's Private Service Connect NAT subnetwork. Consumer traffic is source-NATed into this range, so it must not overlap the producer subnetwork."
  type        = string
  default     = "10.10.100.0/24"
}

variable "consumer_cidr" {
  description = "CIDR range for the consumer subnetwork, which holds the PSC endpoint address and the test instance."
  type        = string
  default     = "10.20.0.0/24"
}

variable "labels" {
  description = "Labels applied to the Compute Engine instances."
  type        = map(string)
  default     = {}
}
