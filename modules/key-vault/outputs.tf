output "kv_id" {
  description = "ID of the key vault."
  value       = azurerm_key_vault.kv.id
}

output "kv_name" {
  description = "Name of the key vault."
  value       = azurerm_key_vault.kv.name
}

output "kv_uri" {
  description = "URI of the key vault, for SDK and app-setting references."
  value       = azurerm_key_vault.kv.vault_uri
}

output "tenant_id" {
  description = "Tenant ID the key vault is bound to."
  value       = azurerm_key_vault.kv.tenant_id
}
