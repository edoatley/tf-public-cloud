output "vm_id" {
  description = "Resource ID of the virtual machine."
  value       = azurerm_linux_virtual_machine.this.id
}

output "vm_name" {
  description = "Name of the virtual machine."
  value       = azurerm_linux_virtual_machine.this.name
}

output "public_ip" {
  description = "Public IP address of the virtual machine."
  value       = azurerm_public_ip.this.ip_address
}

output "private_ip" {
  description = "Private IP address of the network interface."
  value       = azurerm_network_interface.this.private_ip_address
}

output "resource_group_name" {
  description = "Name of the resource group containing all resources."
  value       = azurerm_resource_group.this.name
}

output "ssh_connect_string" {
  description = "SSH command to connect to the VM (supply the private key path)."
  value       = format("ssh -i <private_key> %s@%s", var.admin_username, azurerm_public_ip.this.ip_address)
}
