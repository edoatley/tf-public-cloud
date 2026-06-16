output "function_url" {
  description = "HTTPS endpoint for the Azure Function."
  value       = "https://${azurerm_linux_function_app.this.default_hostname}/api/add"
}

output "function_app_name" {
  description = "Azure Function App name."
  value       = azurerm_linux_function_app.this.name
}
