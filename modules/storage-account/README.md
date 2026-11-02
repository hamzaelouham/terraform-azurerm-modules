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
- Denies all networks by default. Allow what's needed through `sa_network_rules`,
  or set it to `null` to remove the rules. IP rules take public IPv4 addresses or
  CIDRs up to /30; use `virtual_network_subnet_ids` for private ranges.
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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 5.0, < 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 5.0, < 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_private_endpoint.pe](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_storage_account.sa](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.container](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_storage_share.share](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | Azure region, normally the resource group's: module.rg.location. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of an existing resource group to deploy into, e.g. module.rg.name. | `string` | n/a | yes |
| <a name="input_sa_access_tier"></a> [sa\_access\_tier](#input\_sa\_access\_tier) | Default blob access tier: "Hot", "Cool" or "Cold". Applies to Standard StorageV2 accounts only. | `string` | `"Hot"` | no |
| <a name="input_sa_account_kind"></a> [sa\_account\_kind](#input\_sa\_account\_kind) | Account kind: "StorageV2", or "BlockBlobStorage" / "FileStorage" for Premium-only accounts. | `string` | `"StorageV2"` | no |
| <a name="input_sa_account_tier"></a> [sa\_account\_tier](#input\_sa\_account\_tier) | Performance tier: "Standard" or "Premium". | `string` | `"Standard"` | no |
| <a name="input_sa_allow_nested_items_to_be_public"></a> [sa\_allow\_nested\_items\_to\_be\_public](#input\_sa\_allow\_nested\_items\_to\_be\_public) | Allow containers to be made public (access\_type "blob" or "container"). Keep false unless serving public content. | `bool` | `false` | no |
| <a name="input_sa_blob_properties"></a> [sa\_blob\_properties](#input\_sa\_blob\_properties) | Blob data protection. Null keeps Azure defaults (no versioning, no soft delete). Retention days of null leave that soft delete off. Not supported on FileStorage accounts. | <pre>object({<br/>    versioning_enabled              = optional(bool, false)<br/>    delete_retention_days           = optional(number)<br/>    container_delete_retention_days = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_sa_containers"></a> [sa\_containers](#input\_sa\_containers) | Blob containers keyed by name. access\_type is "private" (default), "blob" or "container"; public types need sa\_allow\_nested\_items\_to\_be\_public. | <pre>map(object({<br/>    access_type = optional(string, "private")<br/>  }))</pre> | `{}` | no |
| <a name="input_sa_file_shares"></a> [sa\_file\_shares](#input\_sa\_file\_shares) | File shares keyed by name, with quota\_gb (1-5120) and an optional access\_tier. | <pre>map(object({<br/>    quota_gb    = number<br/>    access_tier = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_sa_name"></a> [sa\_name](#input\_sa\_name) | Name of the storage account. 3-24 lowercase letters and digits, unique across Azure. | `string` | n/a | yes |
| <a name="input_sa_network_rules"></a> [sa\_network\_rules](#input\_sa\_network\_rules) | Network rules, e.g. allowed subnet IDs from module.vnet.subnet\_ids and public IPs. Denies all networks by default; null removes the rules and leaves the account open to all networks allowed by sa\_public\_network\_access\_enabled. | <pre>object({<br/>    default_action             = optional(string, "Deny")<br/>    bypass                     = optional(list(string), ["AzureServices"])<br/>    ip_rules                   = optional(list(string), [])<br/>    virtual_network_subnet_ids = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_sa_private_endpoint"></a> [sa\_private\_endpoint](#input\_sa\_private\_endpoint) | Private endpoint for the blob service. subnet\_id comes from module.vnet.subnet\_ids. private\_dns\_zone\_id is the ID of your own privatelink.blob zone, linked to the vnet; null leaves DNS to you (see sa\_private\_endpoint\_ip). Null creates no endpoint. Not supported on FileStorage accounts. | <pre>object({<br/>    subnet_id           = string<br/>    private_dns_zone_id = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_sa_public_network_access_enabled"></a> [sa\_public\_network\_access\_enabled](#input\_sa\_public\_network\_access\_enabled) | Allow access from public networks, subject to sa\_network\_rules. False allows private endpoints only. | `bool` | `true` | no |
| <a name="input_sa_replication_type"></a> [sa\_replication\_type](#input\_sa\_replication\_type) | Replication: LRS, GRS, RAGRS, ZRS, GZRS or RAGZRS. Premium accounts allow only LRS or ZRS. | `string` | `"LRS"` | no |
| <a name="input_sa_shared_access_key_enabled"></a> [sa\_shared\_access\_key\_enabled](#input\_sa\_shared\_access\_key\_enabled) | Allow access-key (shared key) and SAS authentication. Set false for Entra ID only; callers' azurerm provider then needs storage\_use\_azuread = true for data-plane operations. | `bool` | `true` | no |
| <a name="input_sa_tags"></a> [sa\_tags](#input\_sa\_tags) | Tags to apply to the storage account. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_container_ids"></a> [container\_ids](#output\_container\_ids) | Map of container name to container ID. |
| <a name="output_file_share_ids"></a> [file\_share\_ids](#output\_file\_share\_ids) | Map of file share name to file share ID. |
| <a name="output_sa_id"></a> [sa\_id](#output\_sa\_id) | ID of the storage account, e.g. for role assignments. |
| <a name="output_sa_name"></a> [sa\_name](#output\_sa\_name) | Name of the storage account. |
| <a name="output_sa_primary_blob_endpoint"></a> [sa\_primary\_blob\_endpoint](#output\_sa\_primary\_blob\_endpoint) | Primary blob service endpoint, e.g. https://<name>.blob.core.windows.net/. |
| <a name="output_sa_primary_file_endpoint"></a> [sa\_primary\_file\_endpoint](#output\_sa\_primary\_file\_endpoint) | Primary file service endpoint, e.g. https://<name>.file.core.windows.net/. |
| <a name="output_sa_private_endpoint_id"></a> [sa\_private\_endpoint\_id](#output\_sa\_private\_endpoint\_id) | ID of the private endpoint, or null when sa\_private\_endpoint is null. |
| <a name="output_sa_private_endpoint_ip"></a> [sa\_private\_endpoint\_ip](#output\_sa\_private\_endpoint\_ip) | Private IP of the private endpoint, for callers managing their own DNS record, or null when sa\_private\_endpoint is null. |
<!-- END_TF_DOCS -->