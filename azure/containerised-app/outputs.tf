output "app_fqdn" {
  description = "Fully qualified domain name of the Container App."
  value       = azurerm_container_app.this.latest_revision_fqdn
}

output "app_name" {
  description = "Container App name."
  value       = azurerm_container_app.this.name
}
