terraform {
  required_version = ">= 1.6, < 2.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0, < 4.0"
    }
  }

  backend "gcs" {
    bucket = "tf-public-cloud-gcp-state-edo"
    prefix = "gcp/private-service-connect"
  }
}

provider "google" {
  project = var.project
  region  = var.region
}
