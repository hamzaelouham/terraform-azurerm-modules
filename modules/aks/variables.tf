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
  EOT
  type = object({
    name         = optional(string, "system")
    vm_size      = string
    min_count    = optional(number, 2)
    max_count    = optional(number, 5)
    zones        = optional(list(string))
    os_disk_type = optional(string, "Managed")
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
  description = "ID of a Log Analytics workspace. Set to turn on Container Insights with managed identity auth; null leaves monitoring off."
  type        = string
  default     = null

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", coalesce(var.aks_log_analytics_workspace_id, "/subscriptions/x/resourceGroups/x/providers/Microsoft.OperationalInsights/workspaces/x")))
    error_message = "aks_log_analytics_workspace_id must be a Log Analytics workspace ID: /subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<name>, or null."
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
  description = "Tags for the cluster and its system node pool."
  type        = map(string)
  default     = {}
  nullable    = false
}
