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
