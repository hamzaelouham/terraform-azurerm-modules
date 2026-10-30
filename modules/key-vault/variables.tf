variable "resource_group_name" {
  description = "Name of an existing resource group to deploy into, e.g. module.rg.name."
  type        = string
}

variable "location" {
  description = "Azure region, normally the resource group's: module.rg.location."
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID for the key vault. Null uses the tenant of the current provider credentials."
  type        = string
  default     = null

  validation {
    condition     = var.tenant_id == null || can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "kv_name" {
  description = "Globally unique name of the key vault. 3-24 characters: letters, digits and '-'; must start with a letter, end with a letter or digit, and not contain '--'."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{1,22}[A-Za-z0-9]$", var.kv_name)) && !can(regex("--", var.kv_name))
    error_message = "kv_name must be 3-24 characters of letters, digits or '-', start with a letter, end with a letter or digit, and not contain '--'."
  }
}

variable "kv_sku_name" {
  description = "SKU of the key vault: \"standard\" or \"premium\"."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.kv_sku_name)
    error_message = "kv_sku_name must be \"standard\" or \"premium\"."
  }
}

variable "kv_rbac_authorization_enabled" {
  description = "Use Azure RBAC for data-plane access. When false, access is granted through kv_access_policies."
  type        = bool
  default     = true
  nullable    = false
}

variable "kv_access_policies" {
  description = "Access policies keyed by a descriptive name. Only used when kv_rbac_authorization_enabled is false."
  type = map(object({
    object_id               = string
    key_permissions         = optional(list(string), [])
    secret_permissions      = optional(list(string), [])
    certificate_permissions = optional(list(string), [])
    storage_permissions     = optional(list(string), [])
  }))
  default  = {}
  nullable = false
}

variable "kv_enabled_for_disk_encryption" {
  description = "Allow Azure Disk Encryption to retrieve secrets and unwrap keys."
  type        = bool
  default     = false
  nullable    = false
}

variable "kv_soft_delete_retention_days" {
  description = "Days a deleted vault and its objects are kept before they can be purged (7-90)."
  type        = number
  default     = 90
  nullable    = false

  validation {
    condition     = floor(var.kv_soft_delete_retention_days) == var.kv_soft_delete_retention_days && var.kv_soft_delete_retention_days >= 7 && var.kv_soft_delete_retention_days <= 90
    error_message = "kv_soft_delete_retention_days must be a whole number between 7 and 90."
  }
}

variable "kv_purge_protection_enabled" {
  description = "Block purging of the vault and its objects until the retention period ends. Cannot be turned off once enabled."
  type        = bool
  default     = true
  nullable    = false
}

variable "kv_public_network_access_enabled" {
  description = "Allow access from public networks. Restrict further with kv_network_acls."
  type        = bool
  default     = true
  nullable    = false
}

variable "kv_network_acls" {
  description = "Network rules for the key vault, e.g. allowed subnet IDs from module.vnet.subnet_ids. Null leaves the vault open to all networks allowed by kv_public_network_access_enabled."
  type = object({
    default_action             = optional(string, "Deny")
    bypass                     = optional(string, "AzureServices")
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.kv_network_acls == null || (contains(["Allow", "Deny"], try(var.kv_network_acls.default_action, "")) && contains(["AzureServices", "None"], try(var.kv_network_acls.bypass, "")))
    error_message = "kv_network_acls default_action must be \"Allow\" or \"Deny\", and bypass must be \"AzureServices\" or \"None\"."
  }
}

variable "kv_tags" {
  description = "Tags to apply to the key vault."
  type        = map(string)
  default     = {}
  nullable    = false
}
