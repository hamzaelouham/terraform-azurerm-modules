variable "resource_group_name" {
  description = "Name of an existing resource group to deploy into, e.g. module.rg.name."
  type        = string
}

variable "location" {
  description = "Azure region, normally the resource group's: module.rg.location."
  type        = string
}

variable "sa_name" {
  description = "Name of the storage account. 3-24 lowercase letters and digits, unique across Azure."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.sa_name))
    error_message = "sa_name must be 3-24 lowercase letters and digits."
  }
}

variable "sa_account_tier" {
  description = "Performance tier: \"Standard\" or \"Premium\"."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.sa_account_tier)
    error_message = "sa_account_tier must be \"Standard\" or \"Premium\"."
  }
}

variable "sa_account_kind" {
  description = "Account kind: \"StorageV2\", or \"BlockBlobStorage\" / \"FileStorage\" for Premium-only accounts."
  type        = string
  default     = "StorageV2"

  validation {
    condition     = contains(["StorageV2", "BlockBlobStorage", "FileStorage"], var.sa_account_kind)
    error_message = "sa_account_kind must be \"StorageV2\", \"BlockBlobStorage\" or \"FileStorage\"."
  }
}

variable "sa_replication_type" {
  description = "Replication: LRS, GRS, RAGRS, ZRS, GZRS or RAGZRS. Premium accounts allow only LRS or ZRS."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.sa_replication_type)
    error_message = "sa_replication_type must be LRS, GRS, RAGRS, ZRS, GZRS or RAGZRS."
  }
}

variable "sa_access_tier" {
  description = "Default blob access tier: \"Hot\", \"Cool\" or \"Cold\". Applies to Standard StorageV2 accounts only."
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool", "Cold"], var.sa_access_tier)
    error_message = "sa_access_tier must be \"Hot\", \"Cool\" or \"Cold\"."
  }
}

variable "sa_shared_access_key_enabled" {
  description = "Allow access-key (shared key) and SAS authentication. Set false for Entra ID only; callers' azurerm provider then needs storage_use_azuread = true for data-plane operations."
  type        = bool
  default     = true
  nullable    = false
}

variable "sa_public_network_access_enabled" {
  description = "Allow access from public networks, subject to sa_network_rules. False allows private endpoints only."
  type        = bool
  default     = true
  nullable    = false
}

variable "sa_allow_nested_items_to_be_public" {
  description = "Allow containers to be made public (access_type \"blob\" or \"container\"). Keep false unless serving public content."
  type        = bool
  default     = false
  nullable    = false
}

variable "sa_network_rules" {
  description = "Network rules, e.g. allowed subnet IDs from module.vnet.subnet_ids and public IPs. Null leaves the account open to all networks allowed by sa_public_network_access_enabled."
  type = object({
    default_action             = optional(string, "Deny")
    bypass                     = optional(list(string), ["AzureServices"])
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.sa_network_rules == null || contains(["Allow", "Deny"], try(var.sa_network_rules.default_action, ""))
    error_message = "sa_network_rules default_action must be \"Allow\" or \"Deny\"."
  }

  validation {
    condition = var.sa_network_rules == null || (
      alltrue([for item in try(var.sa_network_rules.bypass, []) : contains(["AzureServices", "Logging", "Metrics", "None"], item)]) &&
      !(contains(try(var.sa_network_rules.bypass, []), "None") && length(try(var.sa_network_rules.bypass, [])) > 1)
    )
    error_message = "sa_network_rules bypass must contain AzureServices, Logging or Metrics, or only None."
  }

  # Storage IP rules take public IPv4 addresses or CIDRs up to /30; Azure rejects
  # /31, /32 and private ranges (use virtual_network_subnet_ids for those). Two
  # blocks overlap when they match once masked to the shorter of their prefixes.
  validation {
    condition = var.sa_network_rules == null || alltrue([
      for ip in try(var.sa_network_rules.ip_rules, []) : try(
        can(regex("^\\d{1,3}(\\.\\d{1,3}){3}(/([0-9]|[12][0-9]|30))?$", ip)) &&
        can(cidrhost("${split("/", ip)[0]}/32", 0)) &&
        !anytrue([
          for range in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] :
          cidrhost("${split("/", ip)[0]}/${min(tonumber(try(split("/", ip)[1], "32")), tonumber(split("/", range)[1]))}", 0) ==
          cidrhost("${split("/", range)[0]}/${min(tonumber(try(split("/", ip)[1], "32")), tonumber(split("/", range)[1]))}", 0)
        ]),
        false
      )
    ])
    error_message = "sa_network_rules ip_rules must be public IPv4 addresses or CIDRs with a prefix of /30 or wider that don't overlap 10.0.0.0/8, 172.16.0.0/12 or 192.168.0.0/16."
  }
}

variable "sa_blob_properties" {
  description = "Blob data protection. Null keeps Azure defaults (no versioning, no soft delete). Retention days of null leave that soft delete off. Not supported on FileStorage accounts."
  type = object({
    versioning_enabled              = optional(bool, false)
    delete_retention_days           = optional(number)
    container_delete_retention_days = optional(number)
  })
  default = null

  validation {
    condition = alltrue([
      for days in [
        coalesce(try(var.sa_blob_properties.delete_retention_days, null), 1),
        coalesce(try(var.sa_blob_properties.container_delete_retention_days, null), 1),
      ] : floor(days) == days && days >= 1 && days <= 365
    ])
    error_message = "sa_blob_properties retention days must be whole numbers from 1 to 365, or null."
  }
}

variable "sa_containers" {
  description = "Blob containers keyed by name. access_type is \"private\" (default), \"blob\" or \"container\"; public types need sa_allow_nested_items_to_be_public."
  type = map(object({
    access_type = optional(string, "private")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for name in keys(var.sa_containers) : length(name) >= 3 && length(name) <= 63 && can(regex("^[a-z0-9](-?[a-z0-9])*$", name))])
    error_message = "sa_containers names must be 3-63 lowercase letters, digits or '-', start and end with a letter or digit, and not contain \"--\"."
  }

  validation {
    condition     = alltrue([for container in var.sa_containers : contains(["private", "blob", "container"], container.access_type)])
    error_message = "sa_containers access_type must be \"private\", \"blob\" or \"container\"."
  }
}

variable "sa_file_shares" {
  description = "File shares keyed by name, with quota_gb (1-5120) and an optional access_tier."
  type = map(object({
    quota_gb    = number
    access_tier = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for name in keys(var.sa_file_shares) : length(name) >= 3 && length(name) <= 63 && can(regex("^[a-z0-9](-?[a-z0-9])*$", name))])
    error_message = "sa_file_shares names must be 3-63 lowercase letters, digits or '-', start and end with a letter or digit, and not contain \"--\"."
  }

  validation {
    condition = alltrue([
      for share in var.sa_file_shares :
      floor(share.quota_gb) == share.quota_gb && share.quota_gb >= 1 && share.quota_gb <= 5120 &&
      contains(["TransactionOptimized", "Hot", "Cool", "Premium"], coalesce(share.access_tier, "Hot"))
    ])
    error_message = "sa_file_shares quota_gb must be a whole number from 1 to 5120, and access_tier null or TransactionOptimized, Hot, Cool or Premium."
  }
}

variable "sa_tags" {
  description = "Tags to apply to the storage account."
  type        = map(string)
  default     = {}
  nullable    = false
}
