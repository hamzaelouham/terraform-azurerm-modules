# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Each module is versioned on its own with a `<module>/vX.Y.Z` git tag, and callers
pin one with `?ref=<module>/vX.Y.Z`. A version heading below lists the module tags
it covers.

## [Unreleased]

_Nothing yet._

## [1.1.0] - 2026-11-08

Covers `resource-group/v1.1.0`. The other modules stay at `v1.0.0`.

### Changed

- `resource-group`: `prevent_destroy` is now `false`, so Terraform no longer
  refuses to destroy or replace the resource group. A `terraform destroy`, or a
  change that forces replacement (such as a new `name` or `location`), now deletes
  the group and everything in it. Callers who need that guard should protect the
  group outside the module, for example with an Azure `CanNotDelete` lock.

## [1.0.0] - 2026-11-05

First release of every module. All seven tags point at commit `1491ed0`:
`resource-group/v1.0.0`, `vnet/v1.0.0`, `key-vault/v1.0.0`,
`service-principal/v1.0.0`, `virtual-machine/v1.0.0`, `storage-account/v1.0.0`
and `aks/v1.0.0`.

### Breaking

Compared with the untagged code that was on `main` before this release:

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
- Every module that uses azurerm now requires azurerm 5.12 or later within 5.x
  (previously 5.0, and 4.0 for `resource-group`), the version the modules were
  checked against. Callers on an older azurerm must upgrade.

### Added

- `resource-group` module: resource group with tags (`rg_tags`) and
  `prevent_destroy`. Outputs `id`, `name` and `location` for the other modules.
  Requires azurerm 5.12 or later within 5.x.
- `vnet` module: virtual network, subnets (`subnets` map, with optional service
  endpoints and NSG association) and one network security group with rules
  (`nsg_rules` map). Deploys into an existing resource group. Requires azurerm
  5.12 or later within 5.x.
- `key-vault` module: key vault with RBAC by default, purge protection on by
  default, optional access policies (`kv_access_policies`) and network rules
  (`kv_network_acls`). Deploys into an existing resource group. Requires azurerm
  5.12 or later within 5.x.
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
  `vm_admin_password` from the caller. Requires azurerm 5.12 or later within 5.x,
  and azapi 2.x.
- `storage-account` module: storage account with HTTPS only, TLS 1.2 and
  infrastructure encryption, public containers off by default, optional network
  rules (`sa_network_rules`) and blob versioning/soft delete
  (`sa_blob_properties`), blob containers (`sa_containers`), file shares
  (`sa_file_shares`) and an optional blob private endpoint (`sa_private_endpoint`)
  with registration in your own private DNS zone. Deploys into an existing
  resource group. Requires azurerm 5.12 or later within 5.x.
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

### Security

Every module passes the Trivy scan at MEDIUM and above. Two MEDIUM rules can't be
satisfied in code on azurerm 5.12 and are accepted in `.trivyignore`, each with
its reason:

- AZU-0057, `storage-account`: no storage logging in the module. Send logs to
  Azure Monitor with a diagnostic setting on the account.
- AZU-0068, `virtual-machine`: the NIC has no NSG of its own. It relies on the
  subnet NSG that `vnet` attaches by default (`associate_nsg = true`).
