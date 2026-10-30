output "vnet_id" {
  description = "ID of the virtual network."
  value       = azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.vnet.name
}

output "vnet_address_space" {
  description = "Address space of the virtual network."
  value       = azurerm_virtual_network.vnet.address_space
}

output "subnet_ids" {
  description = "Map of subnet name to subnet ID."
  value       = { for name, subnet in azurerm_subnet.subnet : name => subnet.id }
}

output "nsg_id" {
  description = "ID of the network security group."
  value       = azurerm_network_security_group.nsg.id
}

output "nsg_name" {
  description = "Name of the network security group."
  value       = azurerm_network_security_group.nsg.name
}
