# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Breaking

- `resource-group`: the `tags` input is renamed to `rg_tags`. Callers passing
  `tags` must switch to `rg_tags`.

### Added

- `vnet` module: virtual network, subnets (`subnets` map, with optional service
  endpoints and NSG association) and one network security group with rules
  (`nsg_rules` map). Deploys into an existing resource group. Requires azurerm 5.x.
- `key-vault` module: key vault with RBAC by default, purge protection on by
  default, optional access policies (`kv_access_policies`) and network rules
  (`kv_network_acls`). Deploys into an existing resource group. Requires azurerm 5.x.
- `service-principal` module: Entra ID application and service principal, with
  optional OIDC federated credentials (`sp_federated_credentials`) and an optional
  rotating client secret (`sp_create_password`). Requires the azuread (3.x) and
  time providers, and an identity allowed to create applications in Entra ID
  (e.g. the `Application.ReadWrite.OwnedBy` Graph permission).
- `virtual-machine` module: Linux or Windows VM (`vm_os_type`) with its own NIC,
  optional public IP, static or dynamic private IP, data disks (`vm_data_disks`,
  including UltraSSD_LRS and PremiumV2_LRS on zonal VMs) and a system-assigned
  managed identity by default. `vm_tags` also reaches the OS disk. Deploys into an
  existing resource group and subnet. Linux uses SSH keys only; Windows takes
  `vm_admin_password` from the caller. Requires azurerm 5.x and azapi 2.x.

### Changed

- `vnet`, `key-vault`, `virtual-machine`: `location` is passed straight to the
  provider (which normalizes it) instead of being normalized and validated in
  each module. Pass `module.rg.location`.
