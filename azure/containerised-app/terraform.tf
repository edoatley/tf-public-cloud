terraform {
  required_version = ">= 1.6, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0, < 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tf-public-cloud-state"
    storage_account_name = "tfpubliccloudazstate"
    container_name       = "tfstate"
    key                  = "azure/containerised-app/terraform.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  use_oidc                        = true
  resource_provider_registrations = "none"
}
