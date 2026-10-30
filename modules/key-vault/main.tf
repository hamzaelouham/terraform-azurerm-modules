data "azurerm_client_config" "current" {}

locals {
  tenant_id = coalesce(var.tenant_id, data.azurerm_client_config.current.tenant_id)
}

resource "azurerm_key_vault" "kv" {
  name                          = var.kv_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = local.tenant_id
  sku_name                      = var.kv_sku_name
  rbac_authorization_enabled    = var.kv_rbac_authorization_enabled
  enabled_for_disk_encryption   = var.kv_enabled_for_disk_encryption
  soft_delete_retention_days    = var.kv_soft_delete_retention_days
  purge_protection_enabled      = var.kv_purge_protection_enabled
  public_network_access_enabled = var.kv_public_network_access_enabled
  tags                          = var.kv_tags

  dynamic "network_acls" {
    for_each = var.kv_network_acls == null ? [] : [var.kv_network_acls]
    content {
      default_action             = network_acls.value.default_action
      bypass                     = network_acls.value.bypass
      ip_rules                   = network_acls.value.ip_rules
      virtual_network_subnet_ids = network_acls.value.virtual_network_subnet_ids
    }
  }

  lifecycle {
    # Access policies are ignored by Azure while RBAC authorization is on.
    precondition {
      condition     = !var.kv_rbac_authorization_enabled || length(var.kv_access_policies) == 0
      error_message = "kv_access_policies can only be set when kv_rbac_authorization_enabled is false."
    }
  }
}

resource "azurerm_key_vault_access_policy" "policy" {
  for_each = var.kv_access_policies

  key_vault_id            = azurerm_key_vault.kv.id
  tenant_id               = local.tenant_id
  object_id               = each.value.object_id
  key_permissions         = each.value.key_permissions
  secret_permissions      = each.value.secret_permissions
  certificate_permissions = each.value.certificate_permissions
  storage_permissions     = each.value.storage_permissions
}
