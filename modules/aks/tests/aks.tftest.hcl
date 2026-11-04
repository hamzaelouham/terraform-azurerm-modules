# Runs offline: the provider is mocked, so these check the module's logic, not Azure.
# The mocks can't fill computed nested blocks, so kubelet_identity stays empty here. The
# kubelet object ID output and the AcrPull assignment (which reads it) therefore can't be
# planned with aks_acr_pull set; only its default (none) and ID validation are tested.
mock_provider "azurerm" {
  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ContainerService/managedClusters/aks-test"
      fqdn            = "aks-test-public.hcp.westeurope.azmk8s.io"
      private_fqdn    = "aks-test-private.privatelink.westeurope.azmk8s.io"
      oidc_issuer_url = "https://westeurope.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/"
    }
  }
  mock_resource "azurerm_role_assignment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/44444444-4444-4444-4444-444444444444"
    }
  }
}

variables {
  resource_group_name  = "rg-test"
  location             = "westeurope"
  subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/aks"
  aks_name             = "aks-test"
  aks_system_node_pool = { vm_size = "Standard_D4ds_v5" }
}

run "defaults_are_secure" {
  command = plan

  assert {
    condition = (
      azurerm_kubernetes_cluster.aks.private_cluster_enabled &&
      azurerm_kubernetes_cluster.aks.private_dns_zone_id == "System" &&
      length(azurerm_kubernetes_cluster.aks.api_server_access_profile) == 0
    )
    error_message = "Expected a private cluster with an AKS-managed DNS zone and no public API profile."
  }
  assert {
    condition = (
      azurerm_kubernetes_cluster.aks.local_account_disabled &&
      azurerm_kubernetes_cluster.aks.role_based_access_control_enabled &&
      azurerm_kubernetes_cluster.aks.azure_active_directory_role_based_access_control[0].azure_rbac_enabled
    )
    error_message = "Expected local accounts off and Entra ID with Azure RBAC on."
  }
  assert {
    condition     = azurerm_kubernetes_cluster.aks.identity[0].type == "SystemAssigned"
    error_message = "Expected a system-assigned identity by default."
  }
  assert {
    condition = (
      azurerm_kubernetes_cluster.aks.network_profile[0].network_plugin == "azure" &&
      azurerm_kubernetes_cluster.aks.network_profile[0].network_plugin_mode == "overlay" &&
      azurerm_kubernetes_cluster.aks.network_profile[0].network_data_plane == "cilium" &&
      azurerm_kubernetes_cluster.aks.network_profile[0].network_policy == "cilium" &&
      azurerm_kubernetes_cluster.aks.network_profile[0].outbound_type == "loadBalancer"
    )
    error_message = "Expected Azure CNI Overlay with the Cilium data plane and policy, outbound through the load balancer."
  }
  assert {
    condition = (
      azurerm_kubernetes_cluster.aks.default_node_pool[0].name == "system" &&
      azurerm_kubernetes_cluster.aks.default_node_pool[0].vnet_subnet_id == var.subnet_id &&
      azurerm_kubernetes_cluster.aks.default_node_pool[0].auto_scaling_enabled &&
      azurerm_kubernetes_cluster.aks.default_node_pool[0].min_count == 2 &&
      azurerm_kubernetes_cluster.aks.default_node_pool[0].max_count == 5 &&
      azurerm_kubernetes_cluster.aks.default_node_pool[0].os_disk_type == "Managed" &&
      azurerm_kubernetes_cluster.aks.default_node_pool[0].temporary_name_for_rotation == "systemtmp"
    )
    error_message = "Expected the system pool in subnet_id, autoscaling 2-5 on managed disks, rotating through systemtmp."
  }
  assert {
    condition = (
      azurerm_kubernetes_cluster.aks.dns_prefix == "aks-test" &&
      azurerm_kubernetes_cluster.aks.sku_tier == "Free" &&
      azurerm_kubernetes_cluster.aks.automatic_upgrade_channel == "patch" &&
      azurerm_kubernetes_cluster.aks.node_os_upgrade_channel == "NodeImage" &&
      azurerm_kubernetes_cluster.aks.node_provisioning_profile[0].mode == "Manual"
    )
    error_message = "Expected the DNS prefix from aks_name, the Free tier, patch and NodeImage upgrades, and manual node provisioning."
  }
  assert {
    condition = (
      !azurerm_kubernetes_cluster.aks.workload_identity_enabled &&
      !azurerm_kubernetes_cluster.aks.oidc_issuer_enabled &&
      length(azurerm_kubernetes_cluster.aks.oms_agent) == 0 &&
      length(azurerm_kubernetes_cluster.aks.key_vault_secrets_provider) == 0 &&
      length(azurerm_role_assignment.acr_pull) == 0
    )
    error_message = "Expected workload identity, Container Insights, the Key Vault CSI driver and ACR pull all off by default."
  }
}

run "default_outputs" {
  command = apply


  assert {
    condition     = output.aks_fqdn == "aks-test-private.privatelink.westeurope.azmk8s.io"
    error_message = "Expected the private FQDN for a private cluster."
  }
  assert {
    condition     = output.aks_identity_principal_id != null && output.aks_oidc_issuer_url == null
    error_message = "Expected a system-assigned principal ID and no OIDC issuer URL by default."
  }
}

run "dns_prefix_and_rotation_name_derivation" {
  command = plan

  variables {
    aks_name             = "aks_with_underscore"
    aks_dns_prefix       = "aks-prefix"
    aks_system_node_pool = { name = "sysnodepool1", vm_size = "Standard_D4ds_v5" }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks.dns_prefix == "aks-prefix"
    error_message = "Expected aks_dns_prefix to override aks_name."
  }
  assert {
    condition     = azurerm_kubernetes_cluster.aks.default_node_pool[0].temporary_name_for_rotation == "sysnodepotmp"
    error_message = "Expected the rotation name to be the first 9 characters plus tmp, within 12 characters."
  }
}

run "rotation_name_differs_from_a_pool_name_ending_in_tmp" {
  command = plan

  variables {
    aks_system_node_pool = { name = "abcdefghitmp", vm_size = "Standard_D4ds_v5" }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks.default_node_pool[0].temporary_name_for_rotation == "abcdefghirot"
    error_message = "Expected the rotation name to switch to the rot suffix when tmp would repeat the pool name."
  }
}

run "constrained_vcpu_vm_size" {
  command = plan

  variables {
    aks_system_node_pool = { vm_size = "Standard_E4-2ds_v5" }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks.default_node_pool[0].vm_size == "Standard_E4-2ds_v5"
    error_message = "Expected a constrained-vCPU size to be accepted."
  }
}

run "public_cluster_with_ranges" {
  command = apply

  variables {
    aks_private_cluster_enabled  = false
    aks_api_authorized_ip_ranges = ["203.0.113.0/24"]
  }

  assert {
    condition = (
      !azurerm_kubernetes_cluster.aks.private_cluster_enabled &&
      contains(azurerm_kubernetes_cluster.aks.api_server_access_profile[0].authorized_ip_ranges, "203.0.113.0/24")
    )
    error_message = "Expected a public API limited to the given range."
  }
  assert {
    condition     = output.aks_fqdn == "aks-test-public.hcp.westeurope.azmk8s.io"
    error_message = "Expected the public FQDN for a public cluster."
  }
}

run "user_assigned_identity_with_custom_dns_zone" {
  command = apply

  variables {
    aks_identity_ids        = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-aks"]
    aks_private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.westeurope.azmk8s.io"
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.aks.identity[0].type == "UserAssigned" &&
      azurerm_kubernetes_cluster.aks.private_dns_zone_id == var.aks_private_dns_zone_id
    )
    error_message = "Expected a user-assigned identity and the custom private DNS zone."
  }
  assert {
    condition     = output.aks_identity_principal_id == null
    error_message = "Expected no system-assigned principal ID with a user-assigned identity."
  }
}

run "network_overrides" {
  command = plan

  variables {
    aks_network = {
      pod_cidr       = "192.168.0.0/16"
      service_cidr   = "172.16.0.0/16"
      dns_service_ip = "172.16.0.10"
      outbound_type  = "userDefinedRouting"
    }
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.aks.network_profile[0].pod_cidr == "192.168.0.0/16" &&
      azurerm_kubernetes_cluster.aks.network_profile[0].service_cidr == "172.16.0.0/16" &&
      azurerm_kubernetes_cluster.aks.network_profile[0].dns_service_ip == "172.16.0.10" &&
      azurerm_kubernetes_cluster.aks.network_profile[0].outbound_type == "userDefinedRouting"
    )
    error_message = "Expected the network overrides to reach network_profile."
  }
}

run "integrations_on" {
  command = apply


  variables {
    aks_workload_identity_enabled  = true
    aks_log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
    aks_key_vault_secrets_provider = { secret_rotation_interval = "5m" }
  }

  assert {
    condition = (
      azurerm_kubernetes_cluster.aks.workload_identity_enabled &&
      azurerm_kubernetes_cluster.aks.oidc_issuer_enabled &&
      output.aks_oidc_issuer_url != null
    )
    error_message = "Expected workload identity and the OIDC issuer on, with its URL output."
  }
  assert {
    condition = (
      azurerm_kubernetes_cluster.aks.oms_agent[0].log_analytics_workspace_id == var.aks_log_analytics_workspace_id &&
      azurerm_kubernetes_cluster.aks.oms_agent[0].msi_auth_for_monitoring_enabled
    )
    error_message = "Expected Container Insights on the given workspace with managed identity auth."
  }
  assert {
    condition = (
      azurerm_kubernetes_cluster.aks.key_vault_secrets_provider[0].secret_rotation_enabled &&
      azurerm_kubernetes_cluster.aks.key_vault_secrets_provider[0].secret_rotation_interval == "5m"
    )
    error_message = "Expected the Key Vault CSI driver with rotation every 5m."
  }
}

run "key_vault_csi_default_interval" {
  command = plan

  variables {
    aks_key_vault_secrets_provider = {}
  }

  assert {
    condition     = azurerm_kubernetes_cluster.aks.key_vault_secrets_provider[0].secret_rotation_interval == "2m"
    error_message = "Expected the default rotation interval of 2m."
  }
}

# Rejected inputs: each must fail at plan time, before anything is created.

run "rejects_bad_subnet_id" {
  command = plan
  variables {
    subnet_id = "/subscriptions/x/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet"
  }
  expect_failures = [var.subnet_id]
}

run "rejects_bad_tenant_id" {
  command = plan
  variables {
    tenant_id = "not-a-guid"
  }
  expect_failures = [var.tenant_id]
}

run "rejects_bad_aks_name" {
  command = plan
  variables {
    aks_name = "-aks"
  }
  expect_failures = [var.aks_name]
}

run "rejects_long_aks_name" {
  command = plan
  variables {
    aks_name = "a234567890123456789012345678901234567890123456789012345678901234"
  }
  expect_failures = [var.aks_name]
}

run "rejects_underscore_in_derived_dns_prefix" {
  command = plan
  variables {
    aks_name = "aks_test"
  }
  expect_failures = [azurerm_kubernetes_cluster.aks]
}

run "rejects_bad_kubernetes_version" {
  command = plan
  variables {
    aks_kubernetes_version = "v1.33"
  }
  expect_failures = [var.aks_kubernetes_version]
}

run "rejects_bad_sku_tier" {
  command = plan
  variables {
    aks_sku_tier = "Basic"
  }
  expect_failures = [var.aks_sku_tier]
}

run "rejects_bad_private_dns_zone_id" {
  command = plan
  variables {
    aks_private_dns_zone_id = "/subscriptions/x/resourceGroups/rg/providers/Microsoft.Network/privateDnsZones/example.com"
  }
  expect_failures = [var.aks_private_dns_zone_id]
}

run "rejects_bad_authorized_range" {
  command = plan
  variables {
    aks_private_cluster_enabled  = false
    aks_api_authorized_ip_ranges = ["203.0.113.4"]
  }
  expect_failures = [var.aks_api_authorized_ip_ranges]
}

run "rejects_two_identities" {
  command = plan
  variables {
    aks_identity_ids = [
      "/subscriptions/x/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/a",
      "/subscriptions/x/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/b",
    ]
  }
  expect_failures = [var.aks_identity_ids]
}

run "rejects_bad_admin_group_id" {
  command = plan
  variables {
    aks_admin_group_object_ids = ["admins"]
  }
  expect_failures = [var.aks_admin_group_object_ids]
}

run "rejects_bad_node_pool_name" {
  command = plan
  variables {
    aks_system_node_pool = { name = "System-Pool", vm_size = "Standard_D4ds_v5" }
  }
  expect_failures = [var.aks_system_node_pool]
}

run "rejects_bad_vm_size" {
  command = plan
  variables {
    aks_system_node_pool = { vm_size = "D4ds_v5" }
  }
  expect_failures = [var.aks_system_node_pool]
}

run "rejects_min_above_max" {
  command = plan
  variables {
    aks_system_node_pool = { vm_size = "Standard_D4ds_v5", min_count = 4, max_count = 3 }
  }
  expect_failures = [var.aks_system_node_pool]
}

run "rejects_zero_min_count" {
  command = plan
  variables {
    aks_system_node_pool = { vm_size = "Standard_D4ds_v5", min_count = 0 }
  }
  expect_failures = [var.aks_system_node_pool]
}

run "rejects_bad_zone" {
  command = plan
  variables {
    aks_system_node_pool = { vm_size = "Standard_D4ds_v5", zones = ["4"] }
  }
  expect_failures = [var.aks_system_node_pool]
}

run "rejects_bad_os_disk_type" {
  command = plan
  variables {
    aks_system_node_pool = { vm_size = "Standard_D4ds_v5", os_disk_type = "Premium" }
  }
  expect_failures = [var.aks_system_node_pool]
}

run "rejects_bad_pod_cidr" {
  command = plan
  variables {
    aks_network = { pod_cidr = "192.168.0.0" }
  }
  expect_failures = [var.aks_network]
}

run "rejects_bad_dns_service_ip" {
  command = plan
  variables {
    aks_network = { service_cidr = "172.16.0.0/16", dns_service_ip = "172.16.0.300" }
  }
  expect_failures = [var.aks_network]
}

run "rejects_bad_outbound_type" {
  command = plan
  variables {
    aks_network = { outbound_type = "none" }
  }
  expect_failures = [var.aks_network]
}

run "rejects_bad_upgrade_channel" {
  command = plan
  variables {
    aks_automatic_upgrade_channel = "latest"
  }
  expect_failures = [var.aks_automatic_upgrade_channel]
}

run "rejects_bad_node_os_upgrade_channel" {
  command = plan
  variables {
    aks_node_os_upgrade_channel = "nodeimage"
  }
  expect_failures = [var.aks_node_os_upgrade_channel]
}

run "rejects_bad_workspace_id" {
  command = plan
  variables {
    aks_log_analytics_workspace_id = "/subscriptions/x/resourceGroups/rg/providers/Microsoft.Insights/components/x"
  }
  expect_failures = [var.aks_log_analytics_workspace_id]
}

run "rejects_bad_rotation_interval" {
  command = plan
  variables {
    aks_key_vault_secrets_provider = { secret_rotation_interval = "2 minutes" }
  }
  expect_failures = [var.aks_key_vault_secrets_provider]
}

run "rejects_bad_acr_registry_id" {
  command = plan
  variables {
    aks_acr_pull = { registry_id = "acrtest.azurecr.io" }
  }
  expect_failures = [var.aks_acr_pull]
}

run "rejects_public_cluster_without_ranges" {
  command = plan
  variables {
    aks_private_cluster_enabled = false
  }
  expect_failures = [azurerm_kubernetes_cluster.aks]
}

run "rejects_private_cluster_with_ranges" {
  command = plan
  variables {
    aks_api_authorized_ip_ranges = ["203.0.113.0/24"]
  }
  expect_failures = [azurerm_kubernetes_cluster.aks]
}

run "rejects_custom_dns_zone_without_user_assigned_identity" {
  command = plan
  variables {
    aks_private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.westeurope.azmk8s.io"
  }
  expect_failures = [azurerm_kubernetes_cluster.aks]
}

run "rejects_service_cidr_without_dns_ip" {
  command = plan
  variables {
    aks_network = { service_cidr = "172.16.0.0/16" }
  }
  expect_failures = [azurerm_kubernetes_cluster.aks]
}

run "rejects_open_authorized_range" {
  command = plan
  variables {
    aks_private_cluster_enabled  = false
    aks_api_authorized_ip_ranges = ["0.0.0.0/0"]
  }
  expect_failures = [var.aks_api_authorized_ip_ranges]
}

run "rejects_dns_service_ip_outside_service_cidr" {
  command = plan
  variables {
    aks_network = { service_cidr = "172.16.0.0/16", dns_service_ip = "10.0.0.10" }
  }
  expect_failures = [azurerm_kubernetes_cluster.aks]
}

run "rejects_node_image_channel_without_node_image_os_channel" {
  command = plan
  variables {
    aks_automatic_upgrade_channel = "node-image"
    aks_node_os_upgrade_channel   = "SecurityPatch"
  }
  expect_failures = [azurerm_kubernetes_cluster.aks]
}

run "rejects_long_explicit_dns_prefix" {
  command = plan
  variables {
    aks_dns_prefix = "a234567890123456789012345678901234567890123456789012345"
  }
  expect_failures = [azurerm_kubernetes_cluster.aks]
}

run "rejects_max_count_above_1000" {
  command = plan
  variables {
    aks_system_node_pool = { vm_size = "Standard_D4ds_v5", max_count = 1001 }
  }
  expect_failures = [var.aks_system_node_pool]
}

run "rejects_fractional_min_count" {
  command = plan
  variables {
    aks_system_node_pool = { vm_size = "Standard_D4ds_v5", min_count = 1.5 }
  }
  expect_failures = [var.aks_system_node_pool]
}
