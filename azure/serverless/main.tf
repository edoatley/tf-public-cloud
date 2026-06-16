resource "random_id" "suffix" {
  byte_length = 2
}

resource "azurerm_resource_group" "this" {
  name     = "${var.resource_group_name}-${random_id.suffix.hex}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "this" {
  name                     = "tfpubcloudfn${random_id.suffix.hex}"
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags
}

resource "azurerm_storage_container" "deployments" {
  name                  = "deployments"
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}

data "archive_file" "function" {
  type        = "zip"
  output_path = "${path.module}/function.zip"

  source {
    content  = file("${path.module}/function_app.py")
    filename = "function_app.py"
  }

  source {
    content  = file("${path.module}/requirements.txt")
    filename = "requirements.txt"
  }

  source {
    content  = file("${path.module}/host.json")
    filename = "host.json"
  }
}

resource "azurerm_storage_blob" "function" {
  name                   = "function-${data.archive_file.function.output_md5}.zip"
  storage_account_name   = azurerm_storage_account.this.name
  storage_container_name = azurerm_storage_container.deployments.name
  type                   = "Block"
  source                 = data.archive_file.function.output_path
}

# Account-level SAS token — read-only, scoped to blob service only.
# Expiry is far future; the token is only used by the Function App runtime
# to download the deployment package from the private container.
data "azurerm_storage_account_sas" "function" {
  connection_string = azurerm_storage_account.this.primary_connection_string
  https_only        = true
  signed_version    = "2017-07-29"

  start  = "2020-01-01T00:00:00Z"
  expiry = "2030-01-01T00:00:00Z"

  resource_types {
    service   = false
    container = false
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  permissions {
    read    = true
    write   = false
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

resource "azurerm_service_plan" "this" {
  name                = "${var.function_app_name}-plan-${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = var.tags
}

resource "azurerm_linux_function_app" "this" {
  name                       = "${var.function_app_name}-${random_id.suffix.hex}"
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  storage_account_name       = azurerm_storage_account.this.name
  storage_account_access_key = azurerm_storage_account.this.primary_access_key
  service_plan_id            = azurerm_service_plan.this.id
  https_only                 = true
  tags                       = var.tags

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME = "python"
    # Blob name includes the source MD5, so this value changes whenever the
    # function code changes — forcing Terraform to update the Function App.
    WEBSITE_RUN_FROM_PACKAGE = "${azurerm_storage_blob.function.url}${data.azurerm_storage_account_sas.function.sas}"
  }
}
