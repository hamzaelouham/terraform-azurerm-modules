# virtual-machine

One Linux or Windows VM (`vm_os_type`) with its NIC, optional public IP, OS disk
and data disks. It deploys into an existing resource group and subnet, so pair it
with the `resource-group` and `vnet` modules.

Requires azurerm 5.x and azapi 2.x (azapi tags the OS disk, which azurerm can't).

```hcl
module "vm" {
  source = "../../modules/virtual-machine"

  resource_group_name = module.rg.name
  location            = module.rg.location
  subnet_id           = module.vnet.subnet_ids["app"]

  vm_os_type = "linux" # or "windows"
  vm_name    = "app-vm"

  # Linux: SSH keys only. Windows: vm_admin_password instead (from a secret store).
  vm_admin_ssh_public_keys = [file("~/.ssh/id_ed25519.pub")]

  vm_private_ip_address = "10.0.1.10" # null = dynamic
  vm_public_ip_enabled  = false       # prefer Bastion or a VPN

  vm_data_disks = {
    data = { lun = 0, disk_size_gb = 64 }
  }
}
```

Notes:

- Windows computer names are limited to 15 characters of letters, digits and
  `-`. Set `vm_computer_name` when `vm_name` doesn't fit.
- UltraSSD_LRS and PremiumV2_LRS data disks need `vm_zone`, and use no caching.
- Run `terraform test` in this directory for offline checks (mocked providers).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.0, < 3.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 5.0, < 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | >= 2.0, < 3.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 5.0, < 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azapi_update_resource.os_disk_tags](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/update_resource) | resource |
| [azurerm_linux_virtual_machine.vm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine) | resource |
| [azurerm_managed_disk.data](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/managed_disk) | resource |
| [azurerm_network_interface.nic](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface) | resource |
| [azurerm_public_ip.pip](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_virtual_machine_data_disk_attachment.data](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine_data_disk_attachment) | resource |
| [azurerm_windows_virtual_machine.vm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/windows_virtual_machine) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | Azure region, normally the resource group's: module.rg.location. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of an existing resource group to deploy into, e.g. module.rg.name. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the subnet for the VM's network interface, e.g. module.vnet.subnet\_ids["app"]. | `string` | n/a | yes |
| <a name="input_vm_accelerated_networking_enabled"></a> [vm\_accelerated\_networking\_enabled](#input\_vm\_accelerated\_networking\_enabled) | Enable accelerated networking on the NIC. Not every VM size supports it. | `bool` | `false` | no |
| <a name="input_vm_admin_password"></a> [vm\_admin\_password](#input\_vm\_admin\_password) | Admin password. Required for Windows, ignored for Linux. Pass it from a secret store, never from source control. | `string` | `null` | no |
| <a name="input_vm_admin_ssh_public_keys"></a> [vm\_admin\_ssh\_public\_keys](#input\_vm\_admin\_ssh\_public\_keys) | SSH public keys for the admin user. Required for Linux; password login is always disabled on Linux. | `list(string)` | `[]` | no |
| <a name="input_vm_admin_username"></a> [vm\_admin\_username](#input\_vm\_admin\_username) | Local administrator username. | `string` | `"azureadmin"` | no |
| <a name="input_vm_boot_diagnostics_enabled"></a> [vm\_boot\_diagnostics\_enabled](#input\_vm\_boot\_diagnostics\_enabled) | Enable boot diagnostics using a managed storage account. | `bool` | `true` | no |
| <a name="input_vm_computer_name"></a> [vm\_computer\_name](#input\_vm\_computer\_name) | Hostname inside the OS. Null uses vm\_name. Windows hostnames are limited to 15 characters. | `string` | `null` | no |
| <a name="input_vm_custom_data"></a> [vm\_custom\_data](#input\_vm\_custom\_data) | Plain-text cloud-init (Linux) or custom data (Windows); base64-encoded by the module. Changing it replaces the VM. | `string` | `null` | no |
| <a name="input_vm_data_disks"></a> [vm\_data\_disks](#input\_vm\_data\_disks) | Data disks keyed by a short name (the disk is named <vm\_name>-<key>). Each LUN must be unique. Caching defaults to ReadWrite, or None for UltraSSD\_LRS, PremiumV2\_LRS and disks of 4096 GB or more, which allow only None. UltraSSD\_LRS and PremiumV2\_LRS need vm\_zone. | <pre>map(object({<br/>    lun                  = number<br/>    disk_size_gb         = number<br/>    storage_account_type = optional(string, "StandardSSD_LRS")<br/>    caching              = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_vm_identity_ids"></a> [vm\_identity\_ids](#input\_vm\_identity\_ids) | User-assigned identity IDs. Required when vm\_identity\_type includes UserAssigned. | `list(string)` | `[]` | no |
| <a name="input_vm_identity_type"></a> [vm\_identity\_type](#input\_vm\_identity\_type) | Managed identity: "SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned", or null for none. | `string` | `"SystemAssigned"` | no |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | Name of the VM. Also prefixes the NIC, public IP and disk names. 1-64 characters: letters, digits, '-' and '.'; must start and end with a letter or digit. | `string` | n/a | yes |
| <a name="input_vm_os_disk"></a> [vm\_os\_disk](#input\_vm\_os\_disk) | OS disk settings. The disk is named <vm\_name>-osdisk. | <pre>object({<br/>    caching              = optional(string, "ReadWrite")<br/>    storage_account_type = optional(string, "StandardSSD_LRS")<br/>    disk_size_gb         = optional(number)<br/>  })</pre> | `{}` | no |
| <a name="input_vm_os_type"></a> [vm\_os\_type](#input\_vm\_os\_type) | Operating system: "linux" or "windows". | `string` | `"linux"` | no |
| <a name="input_vm_private_ip_address"></a> [vm\_private\_ip\_address](#input\_vm\_private\_ip\_address) | Static private IP inside the subnet. Null assigns one dynamically. | `string` | `null` | no |
| <a name="input_vm_public_ip_enabled"></a> [vm\_public\_ip\_enabled](#input\_vm\_public\_ip\_enabled) | Attach a static Standard public IP. Keep false and reach the VM through Bastion or a VPN where possible. | `bool` | `false` | no |
| <a name="input_vm_size"></a> [vm\_size](#input\_vm\_size) | VM size, e.g. "Standard\_B2s\_v2" or "Standard\_D2s\_v5". | `string` | `"Standard_B2s_v2"` | no |
| <a name="input_vm_source_image"></a> [vm\_source\_image](#input\_vm\_source\_image) | Marketplace image. Null uses Ubuntu 24.04 LTS for Linux or Windows Server 2022 Azure Edition for Windows. | <pre>object({<br/>    publisher = string<br/>    offer     = string<br/>    sku       = string<br/>    version   = optional(string, "latest")<br/>  })</pre> | `null` | no |
| <a name="input_vm_source_image_id"></a> [vm\_source\_image\_id](#input\_vm\_source\_image\_id) | ID of a custom or gallery image. Takes the place of vm\_source\_image. | `string` | `null` | no |
| <a name="input_vm_tags"></a> [vm\_tags](#input\_vm\_tags) | Tags to apply to the VM, its NIC, OS and data disks, and public IP. | `map(string)` | `{}` | no |
| <a name="input_vm_trusted_launch_enabled"></a> [vm\_trusted\_launch\_enabled](#input\_vm\_trusted\_launch\_enabled) | Enable Secure Boot and vTPM (Trusted Launch). Needs a Generation 2 image; the default images are Gen 2. | `bool` | `true` | no |
| <a name="input_vm_zone"></a> [vm\_zone](#input\_vm\_zone) | Availability zone ("1", "2" or "3") for the VM, its disks and public IP. Null places them without a zone. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_data_disk_ids"></a> [data\_disk\_ids](#output\_data\_disk\_ids) | Map of data disk key to managed disk ID. |
| <a name="output_identity_principal_id"></a> [identity\_principal\_id](#output\_identity\_principal\_id) | Principal ID of the system-assigned managed identity, for role assignments; null when none is enabled. |
| <a name="output_nic_id"></a> [nic\_id](#output\_nic\_id) | ID of the VM's network interface, e.g. for NSG or load balancer associations. |
| <a name="output_os_disk_id"></a> [os\_disk\_id](#output\_os\_disk\_id) | ID of the OS managed disk. |
| <a name="output_private_ip_address"></a> [private\_ip\_address](#output\_private\_ip\_address) | Private IP address of the VM's network interface. |
| <a name="output_public_ip_address"></a> [public\_ip\_address](#output\_public\_ip\_address) | Public IP address, or null when vm\_public\_ip\_enabled is false. |
| <a name="output_vm_id"></a> [vm\_id](#output\_vm\_id) | ID of the virtual machine. |
| <a name="output_vm_name"></a> [vm\_name](#output\_vm\_name) | Name of the virtual machine. |
<!-- END_TF_DOCS -->