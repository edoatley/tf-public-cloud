data "terraform_remote_state" "registry" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-tf-public-cloud-state"
    storage_account_name = "tfpubliccloudazstate"
    container_name       = "tfstate"
    key                  = "azure/container-registry/terraform.tfstate"
    use_azuread_auth     = true
  }
}

resource "random_id" "suffix" {
  byte_length = 2
}

resource "azurerm_resource_group" "this" {
  name     = "${var.resource_group_name}-${random_id.suffix.hex}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_container_app_environment" "this" {
  name                = "${var.app_name}-env-${random_id.suffix.hex}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_container_app" "this" {
  name                         = var.app_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"
  tags                         = var.tags

  registry {
    server               = data.terraform_remote_state.registry.outputs.login_server
    username             = data.terraform_remote_state.registry.outputs.admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = data.terraform_remote_state.registry.outputs.admin_password
  }

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name   = var.app_name
      image  = "${data.terraform_remote_state.registry.outputs.login_server}/${var.app_name}:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      liveness_probe {
        path      = "/actuator/health"
        port      = 8080
        transport = "HTTP"
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

resource "azurerm_monitor_metric_alert" "app_5xx" {
  name                = "tf-public-cloud-app-5xx-alert"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_container_app.this.id]
  description         = "Alert when any 5xx responses are returned by the Container App"
  severity            = 2
  window_size         = "PT5M"
  frequency           = "PT1M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "Requests"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 0

    dimension {
      name     = "statusCodeCategory"
      operator = "Include"
      values   = ["5xx"]
    }
  }
}
