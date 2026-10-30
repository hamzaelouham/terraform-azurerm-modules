locals {
  is_linux      = var.vm_os_type == "linux"
  computer_name = coalesce(var.vm_computer_name, var.vm_name)

  default_images = {
    linux = {
      publisher = "Canonical"
      offer     = "ubuntu-24_04-lts"
      sku       = "server"
      version   = "latest"
    }
    windows = {
      publisher = "MicrosoftWindowsServer"
      offer     = "WindowsServer"
      sku       = "2022-datacenter-azure-edition"
      version   = "latest"
    }
  }
  # A custom image ID takes precedence; otherwise use the given marketplace image or the OS default.
  source_image = var.vm_source_image_id != null ? null : coalesce(var.vm_source_image, local.default_images[var.vm_os_type])

  custom_data = var.vm_custom_data == null ? null : base64encode(var.vm_custom_data)

  system_identity_enabled = can(regex("SystemAssigned", coalesce(var.vm_identity_type, "-")))

  # Ultra and Premium SSD v2 disks support no host caching and must be zonal; neither do disks of 4 TiB or more.
  uncached_disk_types = ["UltraSSD_LRS", "PremiumV2_LRS"]
  data_disks = {
    for key, disk in var.vm_data_disks : key => merge(disk, {
      name    = "${var.vm_name}-${key}"
      caching = coalesce(disk.caching, contains(local.uncached_disk_types, disk.storage_account_type) || disk.disk_size_gb >= 4096 ? "None" : "ReadWrite")
      # ZRS disks are spread across zones and reject a zone setting.
      zone = endswith(disk.storage_account_type, "_ZRS") ? null : var.vm_zone
    })
  }
  ultra_ssd_enabled = anytrue([for disk in var.vm_data_disks : disk.storage_account_type == "UltraSSD_LRS"])
}

resource "azurerm_public_ip" "pip" {
  count = var.vm_public_ip_enabled ? 1 : 0

  name                = "${var.vm_name}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.vm_zone == null ? null : [var.vm_zone]
  tags                = var.vm_tags
}

resource "azurerm_network_interface" "nic" {
  name                           = "${var.vm_name}-nic"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  accelerated_networking_enabled = var.vm_accelerated_networking_enabled
  tags                           = var.vm_tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = var.vm_private_ip_address == null ? "Dynamic" : "Static"
    private_ip_address            = var.vm_private_ip_address
    public_ip_address_id          = one(azurerm_public_ip.pip[*].id)
  }

  # Checks that span several variables, which variable validation cannot do on Terraform < 1.9.
  lifecycle {
    precondition {
      condition     = var.vm_source_image == null || var.vm_source_image_id == null
      error_message = "Set either vm_source_image or vm_source_image_id, not both."
    }
    precondition {
      condition     = (var.vm_identity_type != null && can(regex("UserAssigned", coalesce(var.vm_identity_type, "-")))) == (length(var.vm_identity_ids) > 0)
      error_message = "vm_identity_ids must be set exactly when vm_identity_type includes UserAssigned."
    }
    precondition {
      condition     = !anytrue([for disk in var.vm_data_disks : contains(local.uncached_disk_types, disk.storage_account_type)]) || var.vm_zone != null
      error_message = "UltraSSD_LRS and PremiumV2_LRS data disks need vm_zone to be set."
    }
    precondition {
      condition     = alltrue([for disk in local.data_disks : length(disk.name) <= 80])
      error_message = "Data disk names (<vm_name>-<key>) must be at most 80 characters; shorten vm_name or the vm_data_disks keys."
    }
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  count = local.is_linux ? 1 : 0

  name                            = var.vm_name
  computer_name                   = local.computer_name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.vm_size
  zone                            = var.vm_zone
  network_interface_ids           = [azurerm_network_interface.nic.id]
  admin_username                  = var.vm_admin_username
  disable_password_authentication = true
  source_image_id                 = var.vm_source_image_id
  custom_data                     = local.custom_data
  secure_boot_enabled             = var.vm_trusted_launch_enabled
  vtpm_enabled                    = var.vm_trusted_launch_enabled
  tags                            = var.vm_tags

  dynamic "admin_ssh_key" {
    for_each = toset(var.vm_admin_ssh_public_keys)
    content {
      username   = var.vm_admin_username
      public_key = admin_ssh_key.value
    }
  }

  os_disk {
    name                 = "${var.vm_name}-osdisk"
    caching              = var.vm_os_disk.caching
    storage_account_type = var.vm_os_disk.storage_account_type
    disk_size_gb         = var.vm_os_disk.disk_size_gb
  }

  dynamic "additional_capabilities" {
    for_each = local.ultra_ssd_enabled ? [1] : []
    content {
      ultra_ssd_enabled = true
    }
  }

  dynamic "source_image_reference" {
    for_each = local.source_image == null ? [] : [local.source_image]
    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  dynamic "identity" {
    for_each = var.vm_identity_type == null ? [] : [var.vm_identity_type]
    content {
      type         = identity.value
      identity_ids = var.vm_identity_ids
    }
  }

  dynamic "boot_diagnostics" {
    for_each = var.vm_boot_diagnostics_enabled ? [1] : []
    content {
      # Null uses a managed storage account.
      storage_account_uri = null
    }
  }

  lifecycle {
    precondition {
      condition     = length(var.vm_admin_ssh_public_keys) > 0
      error_message = "Linux VMs need at least one key in vm_admin_ssh_public_keys; password login is disabled."
    }
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  count = local.is_linux ? 0 : 1

  name                  = var.vm_name
  computer_name         = local.computer_name
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  zone                  = var.vm_zone
  network_interface_ids = [azurerm_network_interface.nic.id]
  admin_username        = var.vm_admin_username
  admin_password        = var.vm_admin_password
  source_image_id       = var.vm_source_image_id
  custom_data           = local.custom_data
  secure_boot_enabled   = var.vm_trusted_launch_enabled
  vtpm_enabled          = var.vm_trusted_launch_enabled
  tags                  = var.vm_tags

  os_disk {
    name                 = "${var.vm_name}-osdisk"
    caching              = var.vm_os_disk.caching
    storage_account_type = var.vm_os_disk.storage_account_type
    disk_size_gb         = var.vm_os_disk.disk_size_gb
  }

  dynamic "additional_capabilities" {
    for_each = local.ultra_ssd_enabled ? [1] : []
    content {
      ultra_ssd_enabled = true
    }
  }

  dynamic "source_image_reference" {
    for_each = local.source_image == null ? [] : [local.source_image]
    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  dynamic "identity" {
    for_each = var.vm_identity_type == null ? [] : [var.vm_identity_type]
    content {
      type         = identity.value
      identity_ids = var.vm_identity_ids
    }
  }

  dynamic "boot_diagnostics" {
    for_each = var.vm_boot_diagnostics_enabled ? [1] : []
    content {
      # Null uses a managed storage account.
      storage_account_uri = null
    }
  }

  lifecycle {
    precondition {
      condition     = var.vm_admin_password != null
      error_message = "Windows VMs need vm_admin_password."
    }
    precondition {
      condition     = can(regex("^[A-Za-z0-9-]{1,15}$", local.computer_name)) && !can(regex("^[0-9]+$", local.computer_name))
      error_message = "Windows computer names must be at most 15 characters of letters, digits or '-' (no '.') and not all digits; set vm_computer_name when vm_name doesn't fit."
    }
  }
}

locals {
  vm_id      = one(concat(azurerm_linux_virtual_machine.vm[*].id, azurerm_windows_virtual_machine.vm[*].id))
  os_disk_id = one(concat([for vm in azurerm_linux_virtual_machine.vm : vm.os_disk[0].id], [for vm in azurerm_windows_virtual_machine.vm : vm.os_disk[0].id]))
}

# The VM resources can't tag the OS disk they create, and Azure doesn't copy the VM's tags to it.
resource "azapi_update_resource" "os_disk_tags" {
  type        = "Microsoft.Compute/disks@2024-03-02"
  resource_id = local.os_disk_id
  body = {
    tags = var.vm_tags
  }
}

resource "azurerm_managed_disk" "data" {
  for_each = local.data_disks

  name                 = each.value.name
  location             = var.location
  resource_group_name  = var.resource_group_name
  zone                 = each.value.zone
  create_option        = "Empty"
  disk_size_gb         = each.value.disk_size_gb
  storage_account_type = each.value.storage_account_type
  tags                 = var.vm_tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each = local.data_disks

  managed_disk_id    = azurerm_managed_disk.data[each.key].id
  virtual_machine_id = local.vm_id
  lun                = each.value.lun
  caching            = each.value.caching
}
