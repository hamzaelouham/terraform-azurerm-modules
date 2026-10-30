output "vm_id" {
  description = "ID of the virtual machine."
  value       = local.vm_id
}

output "vm_name" {
  description = "Name of the virtual machine."
  value       = var.vm_name
}

output "private_ip_address" {
  description = "Private IP address of the VM's network interface."
  value       = azurerm_network_interface.nic.private_ip_address
}

output "public_ip_address" {
  description = "Public IP address, or null when vm_public_ip_enabled is false."
  value       = one(azurerm_public_ip.pip[*].ip_address)
}

output "nic_id" {
  description = "ID of the VM's network interface, e.g. for NSG or load balancer associations."
  value       = azurerm_network_interface.nic.id
}

output "identity_principal_id" {
  description = "Principal ID of the system-assigned managed identity, for role assignments; null when none is enabled."
  # The provider returns "" rather than null for a user-assigned-only identity.
  value = local.system_identity_enabled ? one(concat(
    [for vm in azurerm_linux_virtual_machine.vm : vm.identity[0].principal_id],
    [for vm in azurerm_windows_virtual_machine.vm : vm.identity[0].principal_id]
  )) : null
}

output "os_disk_id" {
  description = "ID of the OS managed disk."
  value       = local.os_disk_id
}

output "data_disk_ids" {
  description = "Map of data disk key to managed disk ID."
  value       = { for key, disk in azurerm_managed_disk.data : key => disk.id }
}
