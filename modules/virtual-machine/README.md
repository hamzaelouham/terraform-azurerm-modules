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
