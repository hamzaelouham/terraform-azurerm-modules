locals {
  dns_prefix    = coalesce(var.aks_dns_prefix, var.aks_name)
  user_assigned = length(var.aks_identity_ids) > 0
  # A zone ID rather than "System" or "None": Azure then needs a user-assigned identity.
  custom_private_dns_zone = var.aks_private_cluster_enabled && !contains(["System", "None"], var.aks_private_dns_zone_id)
  # Used only while AKS cycles the system pool for a resize; follows the same name rules
  # and must differ from the pool name, so a 12-character name ending in "tmp" gets "rot".
  rotation_pool_prefix = substr(var.aks_system_node_pool.name, 0, 9)
  rotation_pool_suffix = "${local.rotation_pool_prefix}tmp" == var.aks_system_node_pool.name ? "rot" : "tmp"
  rotation_pool_name   = "${local.rotation_pool_prefix}${local.rotation_pool_suffix}"

  # Same rule for each user pool's temporary rotation name.
  user_pool_rotation_names = {
    for name in keys(var.aks_user_node_pools) :
    name => "${substr(name, 0, 9)}${"${substr(name, 0, 9)}tmp" == name ? "rot" : "tmp"}"
  }
  all_pool_names  = concat([var.aks_system_node_pool.name], keys(var.aks_user_node_pools))
  cluster_vnet_id = split("/subnets/", lower(var.subnet_id))[0]
  # User pools whose subnet is in another vnet; checked on the cluster so nothing is half-created.
  pools_outside_cluster_vnet = [
    for name, pool in var.aks_user_node_pools : name
    if split("/subnets/", lower(coalesce(pool.subnet_id, var.subnet_id)))[0] != local.cluster_vnet_id
  ]
  spot_label = { "kubernetes.azure.com/scalesetpriority" = "spot" }
  spot_taint = "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = local.dns_prefix
  kubernetes_version  = var.aks_kubernetes_version
  sku_tier            = var.aks_sku_tier

  private_cluster_enabled = var.aks_private_cluster_enabled
  private_dns_zone_id     = var.aks_private_cluster_enabled ? var.aks_private_dns_zone_id : null

  dynamic "api_server_access_profile" {
    for_each = var.aks_private_cluster_enabled ? [] : [1]
    content {
      authorized_ip_ranges = var.aks_api_authorized_ip_ranges
    }
  }

  # Entra ID sign-in with Azure RBAC only: no local admin credentials exist.
  local_account_disabled            = true
  role_based_access_control_enabled = true
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    tenant_id              = var.tenant_id
    admin_group_object_ids = var.aks_admin_group_object_ids
  }

  identity {
    type         = local.user_assigned ? "UserAssigned" : "SystemAssigned"
    identity_ids = local.user_assigned ? var.aks_identity_ids : null
  }

  default_node_pool {
    name                         = var.aks_system_node_pool.name
    vm_size                      = var.aks_system_node_pool.vm_size
    vnet_subnet_id               = var.subnet_id
    auto_scaling_enabled         = true
    min_count                    = var.aks_system_node_pool.min_count
    max_count                    = var.aks_system_node_pool.max_count
    zones                        = var.aks_system_node_pool.zones
    os_disk_type                 = var.aks_system_node_pool.os_disk_type
    temporary_name_for_rotation  = local.rotation_pool_name
    only_critical_addons_enabled = var.aks_system_node_pool.only_critical_addons_enabled
    tags                         = var.aks_tags
  }

  # Required in azurerm 5.x. Manual: this module defines the node pools; "Auto" would
  # turn on node auto-provisioning (Karpenter), which it doesn't support.
  node_provisioning_profile {
    mode = "Manual"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    pod_cidr            = var.aks_network.pod_cidr
    service_cidr        = var.aks_network.service_cidr
    dns_service_ip      = var.aks_network.dns_service_ip
    outbound_type       = var.aks_network.outbound_type
  }

  automatic_upgrade_channel = var.aks_automatic_upgrade_channel == "none" ? null : var.aks_automatic_upgrade_channel
  node_os_upgrade_channel   = var.aks_node_os_upgrade_channel

  oidc_issuer_enabled       = var.aks_workload_identity_enabled
  workload_identity_enabled = var.aks_workload_identity_enabled

  oms_agent {
    log_analytics_workspace_id      = var.aks_log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  dynamic "key_vault_secrets_provider" {
    for_each = var.aks_key_vault_secrets_provider == null ? [] : [var.aks_key_vault_secrets_provider]
    content {
      secret_rotation_enabled  = true
      secret_rotation_interval = key_vault_secrets_provider.value.secret_rotation_interval
    }
  }

  tags = var.aks_tags

  lifecycle {
    precondition {
      condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,52}[A-Za-z0-9])?$", local.dns_prefix))
      error_message = "The DNS prefix (aks_dns_prefix, or aks_name when null) must be 1-54 letters, digits or '-', starting and ending with a letter or digit. Set aks_dns_prefix when aks_name contains '_' or is longer than 54 characters."
    }
    precondition {
      condition     = var.aks_private_cluster_enabled || length(var.aks_api_authorized_ip_ranges) > 0
      error_message = "A public cluster (aks_private_cluster_enabled = false) needs at least one aks_api_authorized_ip_ranges entry, so the API server is never open to the whole internet."
    }
    precondition {
      condition     = !var.aks_private_cluster_enabled || length(var.aks_api_authorized_ip_ranges) == 0
      error_message = "aks_api_authorized_ip_ranges must be empty for a private cluster; Azure supports authorized IP ranges only on a public API server."
    }
    precondition {
      condition     = !local.custom_private_dns_zone || local.user_assigned
      error_message = "A custom aks_private_dns_zone_id needs a user-assigned identity in aks_identity_ids."
    }
    precondition {
      condition     = (var.aks_network.service_cidr == null) == (var.aks_network.dns_service_ip == null)
      error_message = "aks_network service_cidr and dns_service_ip must be set together, or both left null."
    }
    precondition {
      condition = var.aks_network.service_cidr == null || var.aks_network.dns_service_ip == null || try(
        cidrhost("${var.aks_network.dns_service_ip}/${split("/", var.aks_network.service_cidr)[1]}", 0) == cidrhost(var.aks_network.service_cidr, 0),
        false
      )
      error_message = "aks_network dns_service_ip must be inside service_cidr, e.g. \"172.16.0.10\" in \"172.16.0.0/16\"."
    }
    precondition {
      condition     = length(local.pools_outside_cluster_vnet) == 0
      error_message = "aks_user_node_pools subnet_id must be in the same vnet as subnet_id; these pools aren't: ${join(", ", local.pools_outside_cluster_vnet)}."
    }
    precondition {
      condition     = var.aks_automatic_upgrade_channel != "node-image" || var.aks_node_os_upgrade_channel == "NodeImage"
      error_message = "aks_automatic_upgrade_channel \"node-image\" requires aks_node_os_upgrade_channel \"NodeImage\"."
    }
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  for_each = var.aks_user_node_pools

  name                        = each.key
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.aks.id
  mode                        = "User"
  os_type                     = "Linux"
  os_sku                      = each.value.os_sku
  vm_size                     = each.value.vm_size
  vnet_subnet_id              = coalesce(each.value.subnet_id, var.subnet_id)
  auto_scaling_enabled        = true
  min_count                   = each.value.min_count
  max_count                   = each.value.max_count
  zones                       = each.value.zones
  os_disk_type                = each.value.os_disk_type
  temporary_name_for_rotation = local.user_pool_rotation_names[each.key]

  # AKS adds the Spot label and taint itself; declaring them keeps later plans clean.
  priority        = each.value.spot == null ? "Regular" : "Spot"
  eviction_policy = try(each.value.spot.eviction_policy, null)
  spot_max_price  = try(each.value.spot.max_price, null)
  node_labels     = each.value.spot == null ? each.value.node_labels : merge(each.value.node_labels, local.spot_label)
  node_taints     = each.value.spot == null ? each.value.node_taints : distinct(concat(each.value.node_taints, [local.spot_taint]))

  tags = var.aks_tags

  lifecycle {
    precondition {
      condition     = each.key != var.aks_system_node_pool.name
      error_message = "aks_user_node_pools \"${each.key}\": the name is already used by the system pool."
    }
    precondition {
      condition = (
        !contains(local.all_pool_names, local.user_pool_rotation_names[each.key]) &&
        each.key != local.rotation_pool_name &&
        length([for name, rotation in local.user_pool_rotation_names : name if rotation == local.user_pool_rotation_names[each.key]]) == 1 &&
        local.user_pool_rotation_names[each.key] != local.rotation_pool_name
      )
      error_message = "aks_user_node_pools \"${each.key}\": its name or its temporary rotation name (${local.user_pool_rotation_names[each.key]}) collides with another pool's name or rotation name. Rename the pool."
    }
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  # Decided by whether the object is set, not by the ID, which may be unknown until apply.
  count = var.aks_acr_pull == null ? 0 : 1

  scope                = var.aks_acr_pull.registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  principal_type       = "ServicePrincipal"
}
