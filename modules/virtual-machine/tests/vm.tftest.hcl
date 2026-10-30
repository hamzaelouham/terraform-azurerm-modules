# Runs offline: providers are mocked, so these check the module's logic, not Azure.
# Applies need resource IDs the provider can parse; plans don't.
mock_provider "azurerm" {
  mock_resource "azurerm_network_interface" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/networkInterfaces/vm-test-nic"
    }
  }
  mock_resource "azurerm_linux_virtual_machine" {
    defaults = {
      id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Compute/virtualMachines/vm-test"
      os_disk = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Compute/disks/vm-test-osdisk" }
    }
  }
}
mock_provider "azapi" {}

variables {
  resource_group_name      = "rg-test"
  location                 = "westeurope"
  subnet_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/app"
  vm_name                  = "vm-test"
  vm_admin_ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGY0XSjuOw0lceZtoHOtGDnBQijWue9JUjQOUFFwVFuv test@example.com"]
  vm_tags                  = { environment = "test" }
}

run "linux_with_public_ip_static_ip_and_disk" {
  command = plan

  variables {
    vm_public_ip_enabled  = true
    vm_private_ip_address = "10.0.1.10"
    vm_data_disks         = { data = { lun = 0, disk_size_gb = 64 } }
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.vm) == 1 && length(azurerm_windows_virtual_machine.vm) == 0
    error_message = "Expected only a Linux VM."
  }
  assert {
    condition     = length(azurerm_public_ip.pip) == 1
    error_message = "Expected a public IP."
  }
  assert {
    condition     = azurerm_network_interface.nic.ip_configuration[0].private_ip_address_allocation == "Static"
    error_message = "Expected a static private IP."
  }
  assert {
    condition     = azurerm_virtual_machine_data_disk_attachment.data["data"].caching == "ReadWrite"
    error_message = "Expected ReadWrite caching by default."
  }
  assert {
    condition     = azapi_update_resource.os_disk_tags.body.tags == var.vm_tags
    error_message = "Expected the OS disk to get vm_tags."
  }
}

run "windows" {
  command = plan

  variables {
    vm_os_type               = "windows"
    vm_admin_ssh_public_keys = []
    vm_admin_password        = "Correct-Horse-9"
  }

  assert {
    condition     = length(azurerm_windows_virtual_machine.vm) == 1 && length(azurerm_linux_virtual_machine.vm) == 0
    error_message = "Expected only a Windows VM."
  }
  assert {
    condition     = length(azurerm_public_ip.pip) == 0
    error_message = "Expected no public IP by default."
  }
}

run "ultra_disk_gets_capability_no_caching" {
  command = plan

  variables {
    vm_zone       = "1"
    vm_data_disks = { fast = { lun = 0, disk_size_gb = 64, storage_account_type = "UltraSSD_LRS" } }
  }

  assert {
    condition     = azurerm_linux_virtual_machine.vm[0].additional_capabilities[0].ultra_ssd_enabled
    error_message = "Expected ultra_ssd_enabled on the VM."
  }
  assert {
    condition     = azurerm_virtual_machine_data_disk_attachment.data["fast"].caching == "None"
    error_message = "Expected no caching for an Ultra disk."
  }
}

run "zrs_disk_has_no_zone" {
  command = plan

  variables {
    vm_zone       = "2"
    vm_data_disks = { data = { lun = 0, disk_size_gb = 64, storage_account_type = "Premium_ZRS" } }
  }

  assert {
    condition     = azurerm_managed_disk.data["data"].zone == null
    error_message = "Expected ZRS disks to get no zone."
  }
}

run "ultra_disk_without_zone_fails" {
  command = plan
  variables {
    vm_data_disks = { fast = { lun = 0, disk_size_gb = 64, storage_account_type = "UltraSSD_LRS" } }
  }
  expect_failures = [azurerm_network_interface.nic]
}

run "ultra_disk_with_caching_fails" {
  command = plan
  variables {
    vm_zone       = "1"
    vm_data_disks = { fast = { lun = 0, disk_size_gb = 64, storage_account_type = "PremiumV2_LRS", caching = "ReadWrite" } }
  }
  expect_failures = [var.vm_data_disks]
}

run "osdisk_key_fails" {
  command = plan
  variables {
    vm_data_disks = { OsDisk = { lun = 0, disk_size_gb = 64 } }
  }
  expect_failures = [var.vm_data_disks]
}

run "windows_dotted_computer_name_fails" {
  command = plan
  variables {
    vm_os_type               = "windows"
    vm_name                  = "web.01"
    vm_admin_ssh_public_keys = []
    vm_admin_password        = "Correct-Horse-9"
  }
  expect_failures = [azurerm_windows_virtual_machine.vm]
}

run "weak_password_fails" {
  command = plan
  variables {
    vm_os_type        = "windows"
    vm_admin_password = "aaaaaaaaaaaa"
  }
  expect_failures = [var.vm_admin_password]
}

run "banned_password_fails" {
  command = plan
  variables {
    vm_os_type        = "windows"
    vm_admin_password = "P@ssword123"
  }
  expect_failures = [var.vm_admin_password]
}

run "invalid_ip_fails" {
  command = plan
  variables {
    vm_private_ip_address = "10.0.1.999"
  }
  expect_failures = [var.vm_private_ip_address]
}

run "reserved_username_fails" {
  command = plan
  variables {
    vm_admin_username = "Admin1"
  }
  expect_failures = [var.vm_admin_username]
}

run "username_ending_in_dot_fails" {
  command = plan
  variables {
    vm_admin_username = "ops."
  }
  expect_failures = [var.vm_admin_username]
}

run "user_assigned_identity_principal_is_null" {
  command = apply

  variables {
    vm_identity_type = "UserAssigned"
    vm_identity_ids  = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-test"]
  }

  assert {
    condition     = output.identity_principal_id == null
    error_message = "Expected null principal ID without a system-assigned identity."
  }
}
