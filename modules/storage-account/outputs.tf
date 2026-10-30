output "sa_id" {
  description = "ID of the storage account, e.g. for role assignments."
  value       = azurerm_storage_account.sa.id
}

output "sa_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.sa.name
}

output "sa_primary_blob_endpoint" {
  description = "Primary blob service endpoint, e.g. https://<name>.blob.core.windows.net/."
  value       = azurerm_storage_account.sa.primary_blob_endpoint
}

output "sa_primary_file_endpoint" {
  description = "Primary file service endpoint, e.g. https://<name>.file.core.windows.net/."
  value       = azurerm_storage_account.sa.primary_file_endpoint
}

output "container_ids" {
  description = "Map of container name to container ID."
  value       = { for name, container in azurerm_storage_container.container : name => container.id }
}

output "file_share_ids" {
  description = "Map of file share name to file share ID."
  value       = { for name, share in azurerm_storage_share.share : name => share.id }
}

output "sa_private_endpoint_id" {
  description = "ID of the private endpoint, or null when sa_private_endpoint is null."
  value       = one(azurerm_private_endpoint.pe[*].id)
}

output "sa_private_endpoint_ip" {
  description = "Private IP of the private endpoint, for callers managing their own DNS record, or null when sa_private_endpoint is null."
  value       = one(azurerm_private_endpoint.pe[*].private_service_connection[0].private_ip_address)
}
