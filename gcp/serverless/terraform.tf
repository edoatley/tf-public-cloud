terraform {
  required_version = ">= 1.6, < 2.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 7.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0, < 3.0"
    }
  }

  backend "gcs" {
    bucket = "tf-public-cloud-gcp-state-edo"
    prefix = "gcp/serverless"
  }
}

provider "google" {
  project = var.project
  region  = var.region
}
