variable "resource_group_name" {
  description = "Name of the existing resource group the cluster is created in, e.g. module.rg.name."
  type        = string
}

variable "location" {
  description = "Azure region for the cluster, e.g. module.rg.location."
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet the system node pool's nodes join, e.g. module.vnet.subnet_ids[\"aks\"]. With Azure CNI Overlay only nodes take addresses from it, not pods."
  type        = string

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be a subnet resource ID: /subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>."
  }
}

variable "tenant_id" {
  description = "Entra ID tenant for cluster sign-in and Azure RBAC. null uses the tenant of the current subscription."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", coalesce(var.tenant_id, "00000000-0000-0000-0000-000000000000")))
    error_message = "tenant_id must be a GUID, or null."
  }
}

variable "aks_name" {
  description = "Name of the AKS cluster. 1-63 characters: letters, digits, '-' and '_'; must start and end with a letter or digit."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9_-]{0,61}[A-Za-z0-9])?$", var.aks_name))
    error_message = "aks_name must be 1-63 characters of letters, digits, '-' or '_', starting and ending with a letter or digit."
  }
}

variable "aks_dns_prefix" {
  description = "DNS prefix of the API server name. null uses aks_name. 1-54 characters: letters, digits and '-'; must start and end with a letter or digit. Changing it recreates the cluster."
  type        = string
  default     = null
}

variable "aks_kubernetes_version" {
  description = "Kubernetes version, e.g. \"1.33\" or \"1.33.2\". null uses AKS's default version at creation; afterwards aks_automatic_upgrade_channel keeps it current."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", coalesce(var.aks_kubernetes_version, "0.0")))
    error_message = "aks_kubernetes_version must look like \"1.33\" or \"1.33.2\", or be null."
  }
}

variable "aks_sku_tier" {
  description = "AKS pricing tier: \"Free\", \"Standard\" (adds the uptime SLA) or \"Premium\"."
  type        = string
  default     = "Free"
  nullable    = false

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.aks_sku_tier)
    error_message = "aks_sku_tier must be \"Free\", \"Standard\" or \"Premium\"."
  }
}

variable "aks_private_cluster_enabled" {
  description = "Expose the API server only on a private IP in the vnet. Default true. With false, the API is public but limited to aks_api_authorized_ip_ranges, which must then be set."
  type        = bool
  default     = true
  nullable    = false
}

variable "aks_private_dns_zone_id" {
  description = "Private DNS zone for a private cluster: \"System\" (AKS manages it), \"None\" (you run your own DNS), or the ID of a privatelink.<region>.azmk8s.io zone, which needs aks_identity_ids. Ignored for a public cluster."
  type        = string
  default     = "System"
  nullable    = false

  validation {
    condition = contains(["System", "None"], var.aks_private_dns_zone_id) || can(regex(
      "(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/([a-z0-9-]+\\.)?privatelink\\.[a-z0-9]+\\.azmk8s\\.io$",
      var.aks_private_dns_zone_id
    ))
    error_message = "aks_private_dns_zone_id must be \"System\", \"None\" or the ID of a privatelink.<region>.azmk8s.io private DNS zone."
  }
}

variable "aks_api_authorized_ip_ranges" {
  description = "IPv4 CIDRs allowed to reach a public API server, e.g. [\"203.0.113.0/24\"]. Required for a public cluster; must be empty for a private one."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for range in var.aks_api_authorized_ip_ranges : can(cidrnetmask(range)) && try(tonumber(split("/", range)[1]) > 0, false)])
    error_message = "aks_api_authorized_ip_ranges must contain only IPv4 CIDRs such as \"203.0.113.0/24\" or \"203.0.113.4/32\", and never \"0.0.0.0/0\", which would open the API to the whole internet."
  }
}

variable "aks_identity_ids" {
  description = "User-assigned identity for the cluster's control plane, as a one-item list of its ID. Empty uses a system-assigned identity."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = length(var.aks_identity_ids) <= 1 && alltrue([
      for id in var.aks_identity_ids :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ManagedIdentity/userAssignedIdentities/[^/]+$", id))
    ])
    error_message = "aks_identity_ids must hold at most one user-assigned identity ID: /subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<name>."
  }
}

variable "aks_admin_group_object_ids" {
  description = "Object IDs of Entra ID groups that get cluster admin. Empty means admins come only from Azure RBAC role assignments."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for id in var.aks_admin_group_object_ids : can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", id))])
    error_message = "aks_admin_group_object_ids must contain only GUIDs."
  }
}

variable "aks_system_node_pool" {
  description = <<-EOT
    The default (system) node pool, which autoscales between min_count and max_count.
    - name: 1-12 lowercase letters and digits, starting with a letter. Default "system".
    - vm_size: required, e.g. "Standard_D4ds_v5".
    - min_count, max_count: 1-1000, min <= max. Defaults 2 and 5.
    - zones: availability zones, e.g. ["1", "2", "3"]. null uses no zones.
    - os_disk_type: "Managed" (default) or "Ephemeral", which needs a VM size with enough cache or temp disk.
    - only_critical_addons_enabled: true taints the pool with CriticalAddonsOnly, so only system pods run
      there; turn it on once aks_user_node_pools can carry the workloads. Default false. Changing it
      cycles the pool.
  EOT
  type = object({
    name                         = optional(string, "system")
    vm_size                      = string
    min_count                    = optional(number, 2)
    max_count                    = optional(number, 5)
    zones                        = optional(list(string))
    os_disk_type                 = optional(string, "Managed")
    only_critical_addons_enabled = optional(bool, false)
  })
  nullable = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,11}$", var.aks_system_node_pool.name))
    error_message = "aks_system_node_pool name must be 1-12 lowercase letters and digits, starting with a letter."
  }

  validation {
    condition     = can(regex("^Standard_[A-Za-z0-9_-]+$", var.aks_system_node_pool.vm_size))
    error_message = "aks_system_node_pool vm_size must be an Azure VM size such as \"Standard_D4ds_v5\" or \"Standard_E4-2ds_v5\"."
  }

  validation {
    condition = (
      var.aks_system_node_pool.min_count >= 1 &&
      var.aks_system_node_pool.min_count <= var.aks_system_node_pool.max_count &&
      var.aks_system_node_pool.max_count <= 1000 &&
      floor(var.aks_system_node_pool.min_count) == var.aks_system_node_pool.min_count &&
      floor(var.aks_system_node_pool.max_count) == var.aks_system_node_pool.max_count
    )
    error_message = "aks_system_node_pool min_count and max_count must be whole numbers with 1 <= min_count <= max_count <= 1000."
  }

  validation {
    condition     = alltrue([for zone in coalesce(var.aks_system_node_pool.zones, []) : contains(["1", "2", "3"], zone)])
    error_message = "aks_system_node_pool zones may contain only \"1\", \"2\" and \"3\"."
  }

  validation {
    condition     = contains(["Managed", "Ephemeral"], var.aks_system_node_pool.os_disk_type)
    error_message = "aks_system_node_pool os_disk_type must be \"Managed\" or \"Ephemeral\"."
  }
}

variable "aks_user_node_pools" {
  description = <<-EOT
    Linux user node pools for workloads, keyed by pool name (1-12 lowercase letters and digits, starting
    with a letter, not the system pool's name). Each pool autoscales. Default {}: no user pools.
    - vm_size: required, e.g. "Standard_D8ds_v5".
    - min_count, max_count: required whole numbers, 0 <= min <= max <= 1000. 0 lets the pool scale to zero.
    - zones: e.g. ["1", "2", "3"]. null uses no zones.
    - os_disk_type: "Managed" (default) or "Ephemeral".
    - os_sku: "AzureLinux", "AzureLinux3", "Ubuntu", "Ubuntu2204" or "Ubuntu2404". null uses Azure's default.
    - subnet_id: a subnet in the same vnet as subnet_id. null uses subnet_id.
    - node_labels: Kubernetes labels, e.g. { workload = "batch" }.
    - node_taints: e.g. ["workload=batch:NoSchedule"]; effects NoSchedule, PreferNoSchedule or NoExecute.
    - spot: set to use Spot VMs, which Azure can evict at any time, e.g. {} or
      { eviction_policy = "Deallocate", max_price = 0.05 }. eviction_policy "Delete" (default) or
      "Deallocate"; max_price in USD per VM per hour, or -1 (default) for up to the on-demand price.
      Spot pools also get the label and taint AKS puts on Spot nodes, so only pods that tolerate
      kubernetes.azure.com/scalesetpriority=spot:NoSchedule run there.
  EOT
  type = map(object({
    vm_size      = string
    min_count    = number
    max_count    = number
    zones        = optional(list(string))
    os_disk_type = optional(string, "Managed")
    os_sku       = optional(string)
    subnet_id    = optional(string)
    node_labels  = optional(map(string), {})
    node_taints  = optional(list(string), [])
    spot = optional(object({
      eviction_policy = optional(string, "Delete")
      max_price       = optional(number, -1)
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for name in keys(var.aks_user_node_pools) : can(regex("^[a-z][a-z0-9]{0,11}$", name))])
    error_message = "aks_user_node_pools names must be 1-12 lowercase letters and digits, starting with a letter."
  }

  validation {
    condition     = alltrue([for pool in values(var.aks_user_node_pools) : can(regex("^Standard_[A-Za-z0-9_-]+$", pool.vm_size))])
    error_message = "aks_user_node_pools vm_size must be an Azure VM size such as \"Standard_D8ds_v5\"."
  }

  validation {
    condition = alltrue([
      for pool in values(var.aks_user_node_pools) :
      pool.min_count >= 0 && pool.min_count <= pool.max_count && pool.max_count <= 1000 &&
      floor(pool.min_count) == pool.min_count && floor(pool.max_count) == pool.max_count
    ])
    error_message = "aks_user_node_pools min_count and max_count must be whole numbers with 0 <= min_count <= max_count <= 1000."
  }

  validation {
    condition     = alltrue([for pool in values(var.aks_user_node_pools) : alltrue([for zone in coalesce(pool.zones, []) : contains(["1", "2", "3"], zone)])])
    error_message = "aks_user_node_pools zones may contain only \"1\", \"2\" and \"3\"."
  }

  validation {
    condition     = alltrue([for pool in values(var.aks_user_node_pools) : contains(["Managed", "Ephemeral"], pool.os_disk_type)])
    error_message = "aks_user_node_pools os_disk_type must be \"Managed\" or \"Ephemeral\"."
  }

  validation {
    condition     = alltrue([for pool in values(var.aks_user_node_pools) : contains(["AzureLinux", "AzureLinux3", "Ubuntu", "Ubuntu2204", "Ubuntu2404"], coalesce(pool.os_sku, "Ubuntu"))])
    error_message = "aks_user_node_pools os_sku must be \"AzureLinux\", \"AzureLinux3\", \"Ubuntu\", \"Ubuntu2204\" or \"Ubuntu2404\", or null. Windows pools aren't supported: the cluster's Cilium data plane is Linux-only."
  }

  validation {
    condition = alltrue([
      for pool in values(var.aks_user_node_pools) :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", coalesce(pool.subnet_id, "/subscriptions/x/resourceGroups/x/providers/Microsoft.Network/virtualNetworks/x/subnets/x")))
    ])
    error_message = "aks_user_node_pools subnet_id must be a subnet resource ID, or null."
  }

  validation {
    condition = alltrue([
      for pool in values(var.aks_user_node_pools) : alltrue([
        for taint in pool.node_taints : can(regex("^[A-Za-z0-9./_-]+(=[A-Za-z0-9._-]*)?:(NoSchedule|PreferNoSchedule|NoExecute)$", taint))
      ])
    ])
    error_message = "aks_user_node_pools node_taints must look like \"key=value:NoSchedule\" or \"key:NoExecute\", with effect NoSchedule, PreferNoSchedule or NoExecute."
  }

  validation {
    condition     = alltrue([for pool in values(var.aks_user_node_pools) : contains(["Delete", "Deallocate"], try(pool.spot.eviction_policy, "Delete"))])
    error_message = "aks_user_node_pools spot eviction_policy must be \"Delete\" or \"Deallocate\"."
  }

  validation {
    condition = alltrue([
      for pool in values(var.aks_user_node_pools) :
      try(pool.spot.max_price, -1) == -1 || (try(pool.spot.max_price, -1) > 0 && can(regex("^[0-9]+(\\.[0-9]{1,5})?$", tostring(try(pool.spot.max_price, -1)))))
    ])
    error_message = "aks_user_node_pools spot max_price must be -1 (up to the on-demand price) or a positive USD price with at most 5 decimal places."
  }
}

variable "aks_network" {
  description = <<-EOT
    Network settings for Azure CNI Overlay with Cilium. null fields use Azure's defaults.
    - pod_cidr: private range for pod IPs, e.g. "192.168.0.0/16". Must not overlap the vnet.
    - service_cidr, dns_service_ip: set both or neither, e.g. "172.16.0.0/16" and "172.16.0.10". Must not overlap the vnet.
    - outbound_type: "loadBalancer" (default), "userDefinedRouting", "managedNATGateway" or "userAssignedNATGateway".
  EOT
  type = object({
    pod_cidr       = optional(string)
    service_cidr   = optional(string)
    dns_service_ip = optional(string)
    outbound_type  = optional(string, "loadBalancer")
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for cidr in [var.aks_network.pod_cidr, var.aks_network.service_cidr] : can(cidrnetmask(coalesce(cidr, "10.0.0.0/8")))
    ])
    error_message = "aks_network pod_cidr and service_cidr must be IPv4 CIDRs such as \"192.168.0.0/16\", or null."
  }

  validation {
    condition     = can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", coalesce(var.aks_network.dns_service_ip, "10.0.0.10"))) && can(cidrhost("${coalesce(var.aks_network.dns_service_ip, "10.0.0.10")}/32", 0))
    error_message = "aks_network dns_service_ip must be an IPv4 address such as \"172.16.0.10\", or null."
  }

  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting", "managedNATGateway", "userAssignedNATGateway"], var.aks_network.outbound_type)
    error_message = "aks_network outbound_type must be \"loadBalancer\", \"userDefinedRouting\", \"managedNATGateway\" or \"userAssignedNATGateway\"."
  }
}

variable "aks_automatic_upgrade_channel" {
  description = "Kubernetes version upgrade channel: \"patch\" (default), \"rapid\", \"stable\", \"node-image\" or \"none\"."
  type        = string
  default     = "patch"
  nullable    = false

  validation {
    condition     = contains(["patch", "rapid", "stable", "node-image", "none"], var.aks_automatic_upgrade_channel)
    error_message = "aks_automatic_upgrade_channel must be \"patch\", \"rapid\", \"stable\", \"node-image\" or \"none\"."
  }
}

variable "aks_node_os_upgrade_channel" {
  description = "Node OS image upgrade channel: \"NodeImage\" (default), \"SecurityPatch\", \"Unmanaged\" or \"None\"."
  type        = string
  default     = "NodeImage"
  nullable    = false

  validation {
    condition     = contains(["NodeImage", "SecurityPatch", "Unmanaged", "None"], var.aks_node_os_upgrade_channel)
    error_message = "aks_node_os_upgrade_channel must be \"NodeImage\", \"SecurityPatch\", \"Unmanaged\" or \"None\"."
  }
}

variable "aks_workload_identity_enabled" {
  description = "Turn on workload identity and the OIDC issuer, so pods can use federated credentials. Once on, Azure doesn't allow turning the OIDC issuer off again."
  type        = bool
  default     = false
  nullable    = false
}

variable "aks_log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace for Container Insights, which is always on and uses managed identity auth. The workspace bills for the data it ingests."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.aks_log_analytics_workspace_id))
    error_message = "aks_log_analytics_workspace_id must be a Log Analytics workspace ID: /subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<name>."
  }
}

variable "aks_key_vault_secrets_provider" {
  description = "Set to turn on the Key Vault secrets store CSI driver with secret rotation, e.g. {} or { secret_rotation_interval = \"5m\" }. Interval default \"2m\". null leaves it off."
  type = object({
    secret_rotation_interval = optional(string, "2m")
  })
  default = null

  validation {
    condition     = can(regex("^([0-9]+[hms])+$", try(var.aks_key_vault_secrets_provider.secret_rotation_interval, "2m")))
    error_message = "aks_key_vault_secrets_provider secret_rotation_interval must be a duration such as \"2m\", \"30s\" or \"1h30m\"."
  }
}

variable "aks_acr_pull" {
  description = "Set to grant the cluster's kubelet identity AcrPull on a container registry, e.g. { registry_id = azurerm_container_registry.acr.id }. The registry may be created in the same run. null grants nothing."
  type = object({
    registry_id = string
  })
  default = null

  validation {
    condition     = var.aks_acr_pull == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ContainerRegistry/registries/[^/]+$", var.aks_acr_pull.registry_id))
    error_message = "aks_acr_pull registry_id must be a container registry ID: /subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.ContainerRegistry/registries/<name>."
  }
}

variable "aks_tags" {
  description = "Tags for the cluster, its system node pool and every user node pool."
  type        = map(string)
  default     = {}
  nullable    = false
}
