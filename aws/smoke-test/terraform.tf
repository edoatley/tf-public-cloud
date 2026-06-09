terraform {
  required_version = ">= 1.6, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }

  backend "s3" {
    bucket  = "tf-public-cloud-aws-state-edo"
    key     = "aws/smoke-test/terraform.tfstate"
    region  = "eu-west-2"
    encrypt = true
  }
}

provider "aws" {
  region = var.region
}
