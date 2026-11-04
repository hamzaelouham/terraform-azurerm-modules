# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Breaking

- `resource-group`: the `tags` input is renamed to `rg_tags`. Callers passing
  `tags` must switch to `rg_tags`.
- All modules now require Terraform `>= 1.17` (previously `>= 1.3`). Callers on
  older versions must upgrade.
- `key-vault`, `storage-account`: network access is now denied by default
  (`kv_network_acls` and `sa_network_rules` default to `{}`). Callers relying on
  open access must add rules, or pass `null` to remove them.
- `virtual-machine`: the `vm_size` default is now `Standard_B2s_v2`, because
  `Standard_B2s` is flagged for retirement. Existing VMs using the default are
  resized; set `vm_size` to keep the old size.

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
- `storage-account` module: storage account with HTTPS only and TLS 1.2, public
  containers off by default, optional network rules (`sa_network_rules`) and blob
  versioning/soft delete (`sa_blob_properties`), blob containers
  (`sa_containers`), file shares (`sa_file_shares`) and an optional blob private
  endpoint (`sa_private_endpoint`) with registration in your own private DNS zone.
  Deploys into an existing resource group. Requires azurerm 5.x.
- `aks` module: AKS cluster with a system node pool, private by default
  (`aks_private_cluster_enabled`; a public API requires
  `aks_api_authorized_ip_ranges`), Entra ID with Azure RBAC and local accounts off,
  Azure CNI Overlay with Cilium, and Container Insights always on, sending to the
  required Log Analytics workspace in `aks_log_analytics_workspace_id`. Optional
  workload identity (`aks_workload_identity_enabled`), Key Vault secrets CSI driver
  (`aks_key_vault_secrets_provider`) and AcrPull for the kubelet identity
  (`aks_acr_pull`). Deploys into an existing resource group and subnet. Requires
  azurerm 5.12 or later within 5.x.
- `aks` module: Linux user node pools (`aks_user_node_pools`), each autoscaling,
  optionally in its own subnet of the cluster's vnet, and optionally Spot
  (`spot`). The system pool can be reserved for system pods with
  `aks_system_node_pool.only_critical_addons_enabled`.

### Changed

- `vnet`, `key-vault`, `virtual-machine`: `location` is passed straight to the
  provider (which normalizes it) instead of being normalized and validated in
  each module. Pass `module.rg.location`.
