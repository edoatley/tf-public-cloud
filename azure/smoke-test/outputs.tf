output "subscription_id" {
  description = "Azure subscription ID seen by the runner."
  value       = data.azurerm_subscription.current.subscription_id
}

output "subscription_display_name" {
  description = "Display name of the Azure subscription."
  value       = data.azurerm_subscription.current.display_name
}

output "tenant_id" {
  description = "Azure tenant ID."
  value       = data.azurerm_client_config.current.tenant_id
}

output "caller_object_id" {
  description = "Object ID of the identity used by the runner."
  value       = data.azurerm_client_config.current.object_id
}
