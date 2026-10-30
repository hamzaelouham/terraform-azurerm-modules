# storage-account

One storage account with secure defaults, optional network rules and blob data
protection, plus blob containers and file shares. It deploys into an existing
resource group, so pair it with the `resource-group` module (and `vnet` for
subnet rules).

Requires azurerm 5.x.

```hcl
module "storage" {
  source = "../../modules/storage-account"

  resource_group_name = module.rg.name
  location            = module.rg.location
  sa_name             = "stappdata001" # 3-24 lowercase letters/digits, globally unique

  sa_network_rules = {
    ip_rules                   = ["203.0.113.4"]
    virtual_network_subnet_ids = [module.vnet.subnet_ids["app"]]
  }

  sa_blob_properties = { versioning_enabled = true, delete_retention_days = 7 }

  sa_containers  = { data = {} }
  sa_file_shares = { team = { quota_gb = 100 } }
}
```

Defaults:

- Always HTTPS only and TLS 1.2. Containers can't be public unless
  `sa_allow_nested_items_to_be_public = true`.
- Shared key (access key) auth is on. With `sa_shared_access_key_enabled = false`
  the account is Entra ID only, and callers' azurerm provider needs
  `storage_use_azuread = true` for data-plane operations.
- Open to all networks until `sa_network_rules` is set; its `default_action`
  defaults to `Deny`. IP rules take public IPv4 addresses or CIDRs up to /30;
  use `virtual_network_subnet_ids` for private ranges.
- No versioning or soft delete until `sa_blob_properties` is set.

Containers and shares are created through Azure Resource Manager, so Terraform
can still manage them when network rules deny access or shared keys are off.

## Private endpoint

Optional, for the blob service only, so file shares aren't reached through it.

```hcl
sa_private_endpoint = {
  subnet_id           = module.vnet.subnet_ids["endpoints"]
  private_dns_zone_id = azurerm_private_dns_zone.blob.id # privatelink.blob.core.windows.net
}
```

- DNS: the module registers the endpoint in your zone but doesn't create the zone
  or link it to the vnet. Without `private_dns_zone_id`,
  `<account>.blob.core.windows.net` keeps resolving to the public IP until you add
  a record, using the `sa_private_endpoint_ip` output.
- Public access: the endpoint doesn't close it. For private-only access, also set
  `sa_public_network_access_enabled = false`.
- `FileStorage` accounts can't have one, because they have no blob service.

Run `terraform test` in this directory for offline checks (mocked provider).
