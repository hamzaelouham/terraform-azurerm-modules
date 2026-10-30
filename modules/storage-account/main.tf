locals {
  # Hot/Cool/Cold tiers only exist on Standard general-purpose accounts.
  access_tier = var.sa_account_tier == "Standard" && var.sa_account_kind == "StorageV2" ? var.sa_access_tier : null
}

resource "azurerm_storage_account" "sa" {
  name                            = var.sa_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = var.sa_account_tier
  account_kind                    = var.sa_account_kind
  account_replication_type        = var.sa_replication_type
  access_tier                     = local.access_tier
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = var.sa_shared_access_key_enabled
  public_network_access           = var.sa_public_network_access_enabled ? "Enabled" : "Disabled"
  allow_nested_items_to_be_public = var.sa_allow_nested_items_to_be_public
  tags                            = var.sa_tags

  dynamic "network_rules" {
    for_each = var.sa_network_rules == null ? [] : [var.sa_network_rules]
    content {
      default_action             = network_rules.value.default_action
      bypass                     = network_rules.value.bypass
      ip_rules                   = network_rules.value.ip_rules
      virtual_network_subnet_ids = network_rules.value.virtual_network_subnet_ids
    }
  }

  dynamic "blob_properties" {
    for_each = var.sa_blob_properties == null ? [] : [var.sa_blob_properties]
    content {
      versioning_enabled = blob_properties.value.versioning_enabled

      dynamic "delete_retention_policy" {
        for_each = blob_properties.value.delete_retention_days == null ? [] : [blob_properties.value.delete_retention_days]
        content {
          days = delete_retention_policy.value
        }
      }

      dynamic "container_delete_retention_policy" {
        for_each = blob_properties.value.container_delete_retention_days == null ? [] : [blob_properties.value.container_delete_retention_days]
        content {
          days = container_delete_retention_policy.value
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.sa_account_tier == "Standard" || contains(["LRS", "ZRS"], var.sa_replication_type)
      error_message = "Premium storage accounts support only LRS or ZRS replication."
    }
    precondition {
      condition     = var.sa_account_kind == "StorageV2" || var.sa_account_tier == "Premium"
      error_message = "BlockBlobStorage and FileStorage accounts need sa_account_tier = \"Premium\"."
    }
    precondition {
      condition     = var.sa_account_kind != "FileStorage" || length(var.sa_containers) == 0
      error_message = "FileStorage accounts can't hold blob containers; remove sa_containers or use StorageV2."
    }
    precondition {
      condition     = var.sa_account_kind != "BlockBlobStorage" || length(var.sa_file_shares) == 0
      error_message = "BlockBlobStorage accounts can't hold file shares; remove sa_file_shares or use StorageV2."
    }
    precondition {
      condition     = var.sa_account_kind != "FileStorage" || var.sa_blob_properties == null
      error_message = "FileStorage accounts have no blob service; remove sa_blob_properties or use StorageV2."
    }
    precondition {
      condition     = var.sa_account_kind != "FileStorage" || var.sa_private_endpoint == null
      error_message = "FileStorage accounts have no blob service; remove sa_private_endpoint or use StorageV2."
    }
    precondition {
      condition = alltrue([
        for share in var.sa_file_shares :
        var.sa_account_kind == "FileStorage" ? (coalesce(share.access_tier, "Premium") == "Premium" && share.quota_gb >= 100) : share.access_tier != "Premium"
      ])
      error_message = "File shares on FileStorage accounts must use access_tier \"Premium\" (or null) and quota_gb of at least 100; other accounts can't use \"Premium\"."
    }
    precondition {
      condition     = var.sa_allow_nested_items_to_be_public || alltrue([for container in var.sa_containers : container.access_type == "private"])
      error_message = "Containers with access_type \"blob\" or \"container\" need sa_allow_nested_items_to_be_public = true."
    }
  }
}

# Containers and shares take the account ID, so they are managed through ARM and
# still work when network rules deny access or shared keys are disabled.
resource "azurerm_storage_container" "container" {
  for_each = var.sa_containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.sa.id
  container_access_type = each.value.access_type
}

resource "azurerm_storage_share" "share" {
  for_each = var.sa_file_shares

  name               = each.key
  storage_account_id = azurerm_storage_account.sa.id
  quota              = each.value.quota_gb
  access_tier        = each.value.access_tier
}

resource "azurerm_private_endpoint" "pe" {
  count = var.sa_private_endpoint == null ? 0 : 1

  name                = "${var.sa_name}-pe"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.sa_private_endpoint.subnet_id
  tags                = var.sa_tags

  private_service_connection {
    name                           = "${var.sa_name}-psc"
    private_connection_resource_id = azurerm_storage_account.sa.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.sa_private_endpoint.private_dns_zone_id == null ? [] : [var.sa_private_endpoint.private_dns_zone_id]
    content {
      name                 = "${var.sa_name}-dns"
      private_dns_zone_ids = [private_dns_zone_group.value]
    }
  }
}
