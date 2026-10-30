# Runs offline: the provider is mocked, so these check the module's logic, not Azure.
mock_provider "azurerm" {
  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest001"
    }
  }
  mock_resource "azurerm_storage_container" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest001/blobServices/default/containers/mock"
    }
  }
  mock_resource "azurerm_storage_share" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest001/fileServices/default/shares/mock"
    }
  }
}

variables {
  resource_group_name = "rg-test"
  location            = "westeurope"
  sa_name             = "sttest001"
}

run "defaults_are_secure" {
  command = plan

  assert {
    condition = (
      azurerm_storage_account.sa.min_tls_version == "TLS1_2" &&
      azurerm_storage_account.sa.https_traffic_only_enabled &&
      !azurerm_storage_account.sa.allow_nested_items_to_be_public &&
      azurerm_storage_account.sa.shared_access_key_enabled &&
      azurerm_storage_account.sa.public_network_access == "Enabled" &&
      azurerm_storage_account.sa.access_tier == "Hot"
    )
    error_message = "Expected TLS1_2, HTTPS only, no public containers, shared key on, public network on, Hot tier."
  }
  assert {
    condition     = length(azurerm_storage_account.sa.network_rules) == 0 && length(azurerm_storage_account.sa.blob_properties) == 0
    error_message = "Expected no network_rules or blob_properties by default."
  }
  assert {
    condition     = length(azurerm_storage_container.container) == 0 && length(azurerm_storage_share.share) == 0
    error_message = "Expected no containers or shares by default."
  }
}

run "network_rules" {
  command = plan

  variables {
    sa_public_network_access_enabled = false
    sa_network_rules = {
      ip_rules                   = ["203.0.113.4", "198.51.100.0/24"]
      virtual_network_subnet_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/app"]
    }
  }

  assert {
    condition = (
      azurerm_storage_account.sa.network_rules[0].default_action == "Deny" &&
      azurerm_storage_account.sa.network_rules[0].bypass == toset(["AzureServices"]) &&
      length(azurerm_storage_account.sa.network_rules[0].ip_rules) == 2 &&
      length(azurerm_storage_account.sa.network_rules[0].virtual_network_subnet_ids) == 1
    )
    error_message = "Expected Deny with AzureServices bypass, two IP rules and one subnet."
  }
  assert {
    condition     = azurerm_storage_account.sa.public_network_access == "Disabled"
    error_message = "Expected public network access Disabled."
  }
}

run "ip_rules_beside_private_ranges_are_accepted" {
  command = plan

  variables {
    sa_network_rules = { ip_rules = ["172.32.0.1", "11.0.0.0/8"] }
  }

  assert {
    condition     = length(azurerm_storage_account.sa.network_rules[0].ip_rules) == 2
    error_message = "Expected public addresses next to private ranges to be accepted."
  }
}

run "tags_reach_the_account" {
  command = plan

  variables {
    sa_tags = { env = "test" }
  }

  assert {
    condition     = azurerm_storage_account.sa.tags["env"] == "test"
    error_message = "Expected sa_tags on the storage account."
  }
}

run "outputs_map_names_to_ids" {
  command = apply

  variables {
    sa_containers  = { data = {} }
    sa_file_shares = { team-share = { quota_gb = 100 } }
  }

  assert {
    condition     = keys(output.container_ids) == ["data"] && endswith(output.container_ids["data"], "/containers/mock")
    error_message = "Expected container_ids to map the container name to its ID."
  }
  assert {
    condition     = keys(output.file_share_ids) == ["team-share"] && endswith(output.file_share_ids["team-share"], "/shares/mock")
    error_message = "Expected file_share_ids to map the share name to its ID."
  }
}

run "blob_properties" {
  command = plan

  variables {
    sa_blob_properties = { versioning_enabled = true, delete_retention_days = 7, container_delete_retention_days = 14 }
  }

  assert {
    condition = (
      azurerm_storage_account.sa.blob_properties[0].versioning_enabled &&
      azurerm_storage_account.sa.blob_properties[0].delete_retention_policy[0].days == 7 &&
      azurerm_storage_account.sa.blob_properties[0].container_delete_retention_policy[0].days == 14
    )
    error_message = "Expected versioning and both soft-delete policies."
  }
}

run "containers_and_shares" {
  command = plan

  variables {
    sa_allow_nested_items_to_be_public = true
    sa_containers = {
      data   = {}
      public = { access_type = "blob" }
    }
    sa_file_shares = {
      team-share = { quota_gb = 100, access_tier = "Cool" }
    }
  }

  assert {
    condition     = azurerm_storage_container.container["data"].container_access_type == "private" && azurerm_storage_container.container["public"].container_access_type == "blob"
    error_message = "Expected a private and a blob-public container."
  }
  assert {
    condition     = azurerm_storage_share.share["team-share"].quota == 100 && azurerm_storage_share.share["team-share"].access_tier == "Cool"
    error_message = "Expected a 100 GB Cool share."
  }
}

run "premium_filestorage_has_no_access_tier" {
  command = plan

  variables {
    sa_account_tier = "Premium"
    sa_account_kind = "FileStorage"
    sa_file_shares  = { team-share = { quota_gb = 100 } }
  }

  assert {
    condition     = local.access_tier == null
    error_message = "Expected no access tier on a Premium FileStorage account."
  }
}

run "bad_name_fails" {
  command = plan
  variables {
    sa_name = "Bad_Name"
  }
  expect_failures = [var.sa_name]
}

run "bad_container_name_fails" {
  command = plan
  variables {
    sa_containers = { "my--data" = {} }
  }
  expect_failures = [var.sa_containers]
}

run "bad_share_name_fails" {
  command = plan
  variables {
    sa_file_shares = { "-share" = { quota_gb = 10 } }
  }
  expect_failures = [var.sa_file_shares]
}

run "zero_quota_fails" {
  command = plan
  variables {
    sa_file_shares = { share = { quota_gb = 0 } }
  }
  expect_failures = [var.sa_file_shares]
}

run "large_quota_fails" {
  command = plan
  variables {
    sa_file_shares = { share = { quota_gb = 6000 } }
  }
  expect_failures = [var.sa_file_shares]
}

run "private_ip_rule_fails" {
  command = plan
  variables {
    sa_network_rules = { ip_rules = ["10.1.2.3"] }
  }
  expect_failures = [var.sa_network_rules]
}

run "slash_32_ip_rule_fails" {
  command = plan
  variables {
    sa_network_rules = { ip_rules = ["203.0.113.4/32"] }
  }
  expect_failures = [var.sa_network_rules]
}

run "zero_retention_fails" {
  command = plan
  variables {
    sa_blob_properties = { delete_retention_days = 0 }
  }
  expect_failures = [var.sa_blob_properties]
}

run "long_retention_fails" {
  command = plan
  variables {
    sa_blob_properties = { container_delete_retention_days = 400 }
  }
  expect_failures = [var.sa_blob_properties]
}

run "premium_grs_fails" {
  command = plan
  variables {
    sa_account_tier     = "Premium"
    sa_account_kind     = "BlockBlobStorage"
    sa_replication_type = "GRS"
  }
  expect_failures = [azurerm_storage_account.sa]
}

run "standard_filestorage_fails" {
  command = plan
  variables {
    sa_account_kind = "FileStorage"
  }
  expect_failures = [azurerm_storage_account.sa]
}

run "containers_on_filestorage_fail" {
  command = plan
  variables {
    sa_account_tier = "Premium"
    sa_account_kind = "FileStorage"
    sa_containers   = { data = {} }
  }
  expect_failures = [azurerm_storage_account.sa]
}

run "shares_on_blockblobstorage_fail" {
  command = plan
  variables {
    sa_account_tier = "Premium"
    sa_account_kind = "BlockBlobStorage"
    sa_file_shares  = { share = { quota_gb = 100 } }
  }
  expect_failures = [azurerm_storage_account.sa]
}

run "public_container_without_flag_fails" {
  command = plan
  variables {
    sa_containers = { public = { access_type = "container" } }
  }
  expect_failures = [azurerm_storage_account.sa]
}

run "ip_rule_containing_private_range_fails" {
  command = plan
  variables {
    sa_network_rules = { ip_rules = ["172.0.0.0/8"] }
  }
  expect_failures = [var.sa_network_rules]
}

run "ip_rule_everything_fails" {
  command = plan
  variables {
    sa_network_rules = { ip_rules = ["0.0.0.0/0"] }
  }
  expect_failures = [var.sa_network_rules]
}

run "bypass_none_with_other_fails" {
  command = plan
  variables {
    sa_network_rules = { bypass = ["None", "Logging"] }
  }
  expect_failures = [var.sa_network_rules]
}

run "unknown_bypass_fails" {
  command = plan
  variables {
    sa_network_rules = { bypass = ["Foo"] }
  }
  expect_failures = [var.sa_network_rules]
}

run "blob_properties_on_filestorage_fail" {
  command = plan
  variables {
    sa_account_tier    = "Premium"
    sa_account_kind    = "FileStorage"
    sa_blob_properties = { versioning_enabled = true }
  }
  expect_failures = [azurerm_storage_account.sa]
}

run "bad_default_action_fails" {
  command = plan
  variables {
    sa_network_rules = { default_action = "Block" }
  }
  expect_failures = [var.sa_network_rules]
}

run "bad_container_access_type_fails" {
  command = plan
  variables {
    sa_containers = { data = { access_type = "public" } }
  }
  expect_failures = [var.sa_containers]
}

run "bad_share_access_tier_fails" {
  command = plan
  variables {
    sa_file_shares = { share = { quota_gb = 10, access_tier = "Archive" } }
  }
  expect_failures = [var.sa_file_shares]
}

run "premium_share_on_standard_fails" {
  command = plan
  variables {
    sa_file_shares = { share = { quota_gb = 100, access_tier = "Premium" } }
  }
  expect_failures = [azurerm_storage_account.sa]
}

run "hot_share_on_filestorage_fails" {
  command = plan
  variables {
    sa_account_tier = "Premium"
    sa_account_kind = "FileStorage"
    sa_file_shares  = { share = { quota_gb = 100, access_tier = "Hot" } }
  }
  expect_failures = [azurerm_storage_account.sa]
}

run "small_premium_share_fails" {
  command = plan
  variables {
    sa_account_tier = "Premium"
    sa_account_kind = "FileStorage"
    sa_file_shares  = { share = { quota_gb = 50 } }
  }
  expect_failures = [azurerm_storage_account.sa]
}
