variable "resource_group_name" {
  description = "Name of an existing resource group to deploy into, e.g. module.rg.name."
  type        = string
}

variable "location" {
  description = "Azure region, normally the resource group's: module.rg.location."
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet for the VM's network interface, e.g. module.vnet.subnet_ids[\"app\"]."
  type        = string
}

variable "vm_os_type" {
  description = "Operating system: \"linux\" or \"windows\"."
  type        = string
  default     = "linux"

  validation {
    condition     = contains(["linux", "windows"], var.vm_os_type)
    error_message = "vm_os_type must be \"linux\" or \"windows\"."
  }
}

variable "vm_name" {
  description = "Name of the VM. Also prefixes the NIC, public IP and disk names. 1-64 characters: letters, digits, '-' and '.'; must start and end with a letter or digit."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]([-A-Za-z0-9.]{0,62}[A-Za-z0-9])?$", var.vm_name))
    error_message = "vm_name must be 1-64 characters of letters, digits, '-' or '.', and start and end with a letter or digit."
  }
}

variable "vm_computer_name" {
  description = "Hostname inside the OS. Null uses vm_name. Windows hostnames are limited to 15 characters."
  type        = string
  default     = null

  validation {
    condition     = var.vm_computer_name == null || can(regex("^[A-Za-z0-9]([-A-Za-z0-9]{0,62}[A-Za-z0-9])?$", var.vm_computer_name))
    error_message = "vm_computer_name must be 1-64 characters of letters, digits or '-', and start and end with a letter or digit."
  }
}

variable "vm_size" {
  description = "VM size, e.g. \"Standard_B2s\" or \"Standard_D2s_v5\"."
  type        = string
  default     = "Standard_B2s"

  validation {
    condition     = can(regex("^(Standard|Basic)_", var.vm_size))
    error_message = "vm_size must be an Azure VM size such as \"Standard_B2s\"."
  }
}

variable "vm_zone" {
  description = "Availability zone (\"1\", \"2\" or \"3\") for the VM, its disks and public IP. Null places them without a zone."
  type        = string
  default     = null

  validation {
    condition     = var.vm_zone == null || contains(["1", "2", "3"], coalesce(var.vm_zone, "-"))
    error_message = "vm_zone must be \"1\", \"2\", \"3\" or null."
  }
}

variable "vm_admin_username" {
  description = "Local administrator username."
  type        = string
  default     = "azureadmin"
  nullable    = false

  validation {
    condition = (
      can(regex("^[A-Za-z][-A-Za-z0-9_.]{0,19}$", var.vm_admin_username)) && !endswith(var.vm_admin_username, ".") &&
      # Names Azure rejects, plus azureuser.
      !contains([
        "1", "123", "a", "actuser", "adm", "admin", "admin1", "admin2", "administrator", "aspnet", "azureuser",
        "backup", "console", "david", "guest", "john", "owner", "root", "server", "sql", "support",
        "support_388945a0", "sys", "test", "test1", "test2", "test3", "user", "user1", "user2", "user3", "user4", "user5"
      ], lower(var.vm_admin_username))
    )
    error_message = "vm_admin_username must be 1-20 characters, start with a letter, not end with '.', and not be a name Azure reserves such as admin, admin1, root, sql or user1."
  }
}

variable "vm_admin_ssh_public_keys" {
  description = "SSH public keys for the admin user. Required for Linux; password login is always disabled on Linux."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for key in var.vm_admin_ssh_public_keys : can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp(256|384|521)) ", key))])
    error_message = "vm_admin_ssh_public_keys must contain OpenSSH public keys (ssh-rsa, ssh-ed25519 or ecdsa-sha2-*)."
  }
}

variable "vm_admin_password" {
  description = "Admin password. Required for Windows, ignored for Linux. Pass it from a secret store, never from source control."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition = var.vm_admin_password == null || (
      length(coalesce(var.vm_admin_password, "-")) >= 12 && length(coalesce(var.vm_admin_password, "-")) <= 123 &&
      # Azure wants 3 of: lowercase, uppercase, digit, special character.
      length([for class in ["[a-z]", "[A-Z]", "[0-9]", "[^A-Za-z0-9]"] : class if can(regex(class, coalesce(var.vm_admin_password, "-")))]) >= 3 &&
      !contains(["abc@123", "P@$$w0rd", "P@ssw0rd", "P@ssword123", "Pa$$word", "pass@word1", "Password!", "Password1", "Password22", "iloveyou!"], coalesce(var.vm_admin_password, "-"))
    )
    error_message = "vm_admin_password must be 12-123 characters with at least 3 of: lowercase letter, uppercase letter, digit, special character; and must not be a password Azure rejects, such as P@ssw0rd."
  }
}

variable "vm_source_image" {
  description = "Marketplace image. Null uses Ubuntu 24.04 LTS for Linux or Windows Server 2022 Azure Edition for Windows."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = optional(string, "latest")
  })
  default = null
}

variable "vm_source_image_id" {
  description = "ID of a custom or gallery image. Takes the place of vm_source_image."
  type        = string
  default     = null
}

variable "vm_os_disk" {
  description = "OS disk settings. The disk is named <vm_name>-osdisk."
  type = object({
    caching              = optional(string, "ReadWrite")
    storage_account_type = optional(string, "StandardSSD_LRS")
    disk_size_gb         = optional(number)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["None", "ReadOnly", "ReadWrite"], var.vm_os_disk.caching) && contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "StandardSSD_ZRS", "Premium_ZRS"], var.vm_os_disk.storage_account_type)
    error_message = "vm_os_disk caching must be None, ReadOnly or ReadWrite; storage_account_type must be Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS or Premium_ZRS."
  }
}

variable "vm_data_disks" {
  description = "Data disks keyed by a short name (the disk is named <vm_name>-<key>). Each LUN must be unique. Caching defaults to ReadWrite, or None for UltraSSD_LRS, PremiumV2_LRS and disks of 4096 GB or more, which allow only None. UltraSSD_LRS and PremiumV2_LRS need vm_zone."
  type = map(object({
    lun                  = number
    disk_size_gb         = number
    storage_account_type = optional(string, "StandardSSD_LRS")
    caching              = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for key in keys(var.vm_data_disks) : can(regex("^[A-Za-z0-9]([-\\w.]*\\w)?$", key)) && lower(key) != "osdisk"])
    error_message = "vm_data_disks keys must be letters, digits, '_', '-' or '.', start with a letter or digit, end with a letter, digit or '_', and not be \"osdisk\" (the OS disk's name)."
  }

  validation {
    condition     = length(distinct([for disk in var.vm_data_disks : disk.lun])) == length(var.vm_data_disks)
    error_message = "vm_data_disks LUNs must be unique."
  }

  validation {
    condition = alltrue([
      for disk in var.vm_data_disks :
      floor(disk.lun) == disk.lun && disk.lun >= 0 && disk.lun <= 63 && disk.disk_size_gb >= 1 &&
      contains(["None", "ReadOnly", "ReadWrite"], coalesce(disk.caching, "None")) &&
      contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "PremiumV2_LRS", "UltraSSD_LRS", "StandardSSD_ZRS", "Premium_ZRS"], disk.storage_account_type)
    ])
    error_message = "Each vm_data_disks entry needs a whole-number lun of 0-63, disk_size_gb of at least 1, a valid caching mode and a valid storage_account_type."
  }

  validation {
    condition = alltrue([
      for disk in var.vm_data_disks :
      coalesce(disk.caching, "None") == "None" || !(contains(["UltraSSD_LRS", "PremiumV2_LRS"], disk.storage_account_type) || disk.disk_size_gb >= 4096)
    ])
    error_message = "vm_data_disks caching must be None (or unset) for UltraSSD_LRS and PremiumV2_LRS disks and for disks of 4096 GB or more."
  }
}

variable "vm_public_ip_enabled" {
  description = "Attach a static Standard public IP. Keep false and reach the VM through Bastion or a VPN where possible."
  type        = bool
  default     = false
  nullable    = false
}

variable "vm_private_ip_address" {
  description = "Static private IP inside the subnet. Null assigns one dynamically."
  type        = string
  default     = null

  validation {
    condition     = var.vm_private_ip_address == null || (can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", coalesce(var.vm_private_ip_address, "-"))) && can(cidrhost("${coalesce(var.vm_private_ip_address, "-")}/32", 0)))
    error_message = "vm_private_ip_address must be an IPv4 address."
  }
}

variable "vm_accelerated_networking_enabled" {
  description = "Enable accelerated networking on the NIC. Not every VM size supports it."
  type        = bool
  default     = false
  nullable    = false
}

variable "vm_identity_type" {
  description = "Managed identity: \"SystemAssigned\", \"UserAssigned\", \"SystemAssigned, UserAssigned\", or null for none."
  type        = string
  default     = "SystemAssigned"

  validation {
    condition     = var.vm_identity_type == null || contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], coalesce(var.vm_identity_type, "-"))
    error_message = "vm_identity_type must be \"SystemAssigned\", \"UserAssigned\", \"SystemAssigned, UserAssigned\" or null."
  }
}

variable "vm_identity_ids" {
  description = "User-assigned identity IDs. Required when vm_identity_type includes UserAssigned."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "vm_trusted_launch_enabled" {
  description = "Enable Secure Boot and vTPM (Trusted Launch). Needs a Generation 2 image; the default images are Gen 2."
  type        = bool
  default     = true
  nullable    = false
}

variable "vm_boot_diagnostics_enabled" {
  description = "Enable boot diagnostics using a managed storage account."
  type        = bool
  default     = true
  nullable    = false
}

variable "vm_custom_data" {
  description = "Plain-text cloud-init (Linux) or custom data (Windows); base64-encoded by the module. Changing it replaces the VM."
  type        = string
  default     = null
  sensitive   = true
}

variable "vm_tags" {
  description = "Tags to apply to the VM, its NIC, OS and data disks, and public IP."
  type        = map(string)
  default     = {}
  nullable    = false
}
