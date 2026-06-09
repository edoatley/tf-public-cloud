resource "random_id" "suffix" {
  byte_length = 2
}

resource "azurerm_resource_group" "this" {
  name     = "${var.resource_group_name}-${random_id.suffix.hex}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "this" {
  name                = "${var.storage_account_name}${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  account_tier             = "Standard"
  account_replication_type = var.account_replication_type

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "this" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
