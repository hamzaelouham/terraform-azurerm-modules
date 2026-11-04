# aks

One AKS cluster with a system node pool, private by default, using Entra ID with
Azure RBAC and no local accounts. Pods use Azure CNI Overlay with Cilium. It
deploys into an existing resource group and a subnet, so pair it with the
`resource-group` and `vnet` modules.

Requires azurerm 5.12 or later within 5.x.

```hcl
module "aks" {
  source = "../../modules/aks"

  resource_group_name = module.rg.name
  location            = module.rg.location
  subnet_id           = module.vnet.subnet_ids["aks"]
  aks_name            = "aks-app-prod"

  aks_system_node_pool = {
    vm_size = "Standard_D4ds_v5"
    zones   = ["1", "2", "3"]
  }

  aks_admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"] # an Entra ID group

  aks_log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id # Container Insights

  # Optional integrations, each off by default:
  aks_workload_identity_enabled  = true
  aks_key_vault_secrets_provider = {}
  aks_acr_pull                   = { registry_id = azurerm_container_registry.acr.id }
}
```

Defaults:

- **Private API server.** The API has only a private IP in the vnet, and AKS
  manages its private DNS zone (`System`). Terraform and `kubectl` must run from a
  network that can reach and resolve it: the vnet, a peered vnet, or a VPN. GitHub-
  hosted runners can't. For a public API set `aks_private_cluster_enabled = false`;
  `aks_api_authorized_ip_ranges` is then required, so the API is never open to the
  whole internet.
- **Entra ID only.** Local accounts are off and there's no kubeconfig output. Use
  `az aks get-credentials` with `kubelogin`, and grant access through Azure RBAC
  roles such as "Azure Kubernetes Service RBAC Cluster Admin", or
  `aks_admin_group_object_ids`.
- **System-assigned identity.** Pass one user-assigned identity in
  `aks_identity_ids` instead. That's required for a custom `aks_private_dns_zone_id`.
- **Network.** Azure CNI Overlay with the Cilium data plane and network policy.
  Only nodes take IPs from the subnet. Pod and service ranges use Azure's defaults
  unless `aks_network` sets them; neither may overlap the vnet.
- **System pool** autoscales from 2 to 5 nodes and has no taint, so workloads run
  on it until you add user node pools.
- **Upgrades:** Kubernetes patch versions automatically (`patch`), and node images
  (`NodeImage`).
- **Free tier.** Use `aks_sku_tier = "Standard"` for the uptime SLA.
- **Container Insights on.** Logs and metrics go to the Log Analytics workspace in
  `aks_log_analytics_workspace_id`, which is required, using managed identity auth.
  The workspace bills for the data it ingests, so size its retention and daily cap
  for your environment.

## User node pools

Optional Linux pools for your workloads, keyed by name. Each autoscales between
`min_count` and `max_count`; `0` lets a pool scale to zero.

```hcl
aks_user_node_pools = {
  apps = {
    vm_size   = "Standard_D8ds_v5"
    min_count = 1
    max_count = 10
    zones     = ["1", "2", "3"]
  }
  batch = {
    vm_size     = "Standard_D8ds_v5"
    min_count   = 0
    max_count   = 20
    subnet_id   = module.vnet.subnet_ids["batch"] # same vnet as subnet_id
    node_taints = ["workload=batch:NoSchedule"]
    spot        = {} # Spot VMs at up to the on-demand price, deleted on eviction
  }
}

# Once user pools carry the workloads, keep the system pool for system pods only:
aks_system_node_pool = { vm_size = "Standard_D4ds_v5", only_critical_addons_enabled = true }
```

- **Linux only.** The cluster's Cilium data plane doesn't support Windows nodes.
- **Spot pools** can be evicted at any time. The module adds the label and taint
  AKS puts on Spot nodes, `kubernetes.azure.com/scalesetpriority=spot:NoSchedule`,
  so only pods with a matching toleration run there.
- **Versions** follow the cluster: pools take no Kubernetes version of their own and
  are upgraded through `aks_automatic_upgrade_channel`.
- **Changes that cycle a pool**, such as `vm_size`, `zones`, `os_disk_type` or
  `subnet_id`, go through a temporary pool named from the pool's first 9
  characters plus `tmp`. The plan fails if two pools would share that name.
- **Turning on `only_critical_addons_enabled`** also cycles the system pool. Pods
  without a `CriticalAddonsOnly` toleration move to user pools, so make sure one exists.

Roles the caller grants. This module only creates the AcrPull assignment.

- The cluster identity (`aks_identity_principal_id`, or your user-assigned identity)
  may need **Network Contributor** on the subnet, for example for internal load
  balancers. A custom private DNS zone also needs **Private DNS Zone Contributor**
  on that zone.
- Workloads using the Key Vault CSI driver need a Key Vault role, such as
  "Key Vault Secrets User", for the identity they use.

Nothing here is tested against Azure: `terraform test` in this directory runs
offline with a mocked provider. Run a real `plan` and `apply` before relying on
it.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 5.12, < 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 5.12, < 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_kubernetes_cluster.aks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_kubernetes_cluster_node_pool.user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool) | resource |
| [azurerm_role_assignment.acr_pull](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aks_acr_pull"></a> [aks\_acr\_pull](#input\_aks\_acr\_pull) | Set to grant the cluster's kubelet identity AcrPull on a container registry, e.g. { registry\_id = azurerm\_container\_registry.acr.id }. The registry may be created in the same run. null grants nothing. | <pre>object({<br/>    registry_id = string<br/>  })</pre> | `null` | no |
| <a name="input_aks_admin_group_object_ids"></a> [aks\_admin\_group\_object\_ids](#input\_aks\_admin\_group\_object\_ids) | Object IDs of Entra ID groups that get cluster admin. Empty means admins come only from Azure RBAC role assignments. | `list(string)` | `[]` | no |
| <a name="input_aks_api_authorized_ip_ranges"></a> [aks\_api\_authorized\_ip\_ranges](#input\_aks\_api\_authorized\_ip\_ranges) | IPv4 CIDRs allowed to reach a public API server, e.g. ["203.0.113.0/24"]. Required for a public cluster; must be empty for a private one. | `set(string)` | `[]` | no |
| <a name="input_aks_automatic_upgrade_channel"></a> [aks\_automatic\_upgrade\_channel](#input\_aks\_automatic\_upgrade\_channel) | Kubernetes version upgrade channel: "patch" (default), "rapid", "stable", "node-image" or "none". | `string` | `"patch"` | no |
| <a name="input_aks_dns_prefix"></a> [aks\_dns\_prefix](#input\_aks\_dns\_prefix) | DNS prefix of the API server name. null uses aks\_name. 1-54 characters: letters, digits and '-'; must start and end with a letter or digit. Changing it recreates the cluster. | `string` | `null` | no |
| <a name="input_aks_identity_ids"></a> [aks\_identity\_ids](#input\_aks\_identity\_ids) | User-assigned identity for the cluster's control plane, as a one-item list of its ID. Empty uses a system-assigned identity. | `list(string)` | `[]` | no |
| <a name="input_aks_key_vault_secrets_provider"></a> [aks\_key\_vault\_secrets\_provider](#input\_aks\_key\_vault\_secrets\_provider) | Set to turn on the Key Vault secrets store CSI driver with secret rotation, e.g. {} or { secret\_rotation\_interval = "5m" }. Interval default "2m". null leaves it off. | <pre>object({<br/>    secret_rotation_interval = optional(string, "2m")<br/>  })</pre> | `null` | no |
| <a name="input_aks_kubernetes_version"></a> [aks\_kubernetes\_version](#input\_aks\_kubernetes\_version) | Kubernetes version, e.g. "1.33" or "1.33.2". null uses AKS's default version at creation; afterwards aks\_automatic\_upgrade\_channel keeps it current. | `string` | `null` | no |
| <a name="input_aks_log_analytics_workspace_id"></a> [aks\_log\_analytics\_workspace\_id](#input\_aks\_log\_analytics\_workspace\_id) | ID of the Log Analytics workspace for Container Insights, which is always on and uses managed identity auth. The workspace bills for the data it ingests. | `string` | n/a | yes |
| <a name="input_aks_name"></a> [aks\_name](#input\_aks\_name) | Name of the AKS cluster. 1-63 characters: letters, digits, '-' and '\_'; must start and end with a letter or digit. | `string` | n/a | yes |
| <a name="input_aks_network"></a> [aks\_network](#input\_aks\_network) | Network settings for Azure CNI Overlay with Cilium. null fields use Azure's defaults.<br/>- pod\_cidr: private range for pod IPs, e.g. "192.168.0.0/16". Must not overlap the vnet.<br/>- service\_cidr, dns\_service\_ip: set both or neither, e.g. "172.16.0.0/16" and "172.16.0.10". Must not overlap the vnet.<br/>- outbound\_type: "loadBalancer" (default), "userDefinedRouting", "managedNATGateway" or "userAssignedNATGateway". | <pre>object({<br/>    pod_cidr       = optional(string)<br/>    service_cidr   = optional(string)<br/>    dns_service_ip = optional(string)<br/>    outbound_type  = optional(string, "loadBalancer")<br/>  })</pre> | `{}` | no |
| <a name="input_aks_node_os_upgrade_channel"></a> [aks\_node\_os\_upgrade\_channel](#input\_aks\_node\_os\_upgrade\_channel) | Node OS image upgrade channel: "NodeImage" (default), "SecurityPatch", "Unmanaged" or "None". | `string` | `"NodeImage"` | no |
| <a name="input_aks_private_cluster_enabled"></a> [aks\_private\_cluster\_enabled](#input\_aks\_private\_cluster\_enabled) | Expose the API server only on a private IP in the vnet. Default true. With false, the API is public but limited to aks\_api\_authorized\_ip\_ranges, which must then be set. | `bool` | `true` | no |
| <a name="input_aks_private_dns_zone_id"></a> [aks\_private\_dns\_zone\_id](#input\_aks\_private\_dns\_zone\_id) | Private DNS zone for a private cluster: "System" (AKS manages it), "None" (you run your own DNS), or the ID of a privatelink.<region>.azmk8s.io zone, which needs aks\_identity\_ids. Ignored for a public cluster. | `string` | `"System"` | no |
| <a name="input_aks_sku_tier"></a> [aks\_sku\_tier](#input\_aks\_sku\_tier) | AKS pricing tier: "Free", "Standard" (adds the uptime SLA) or "Premium". | `string` | `"Free"` | no |
| <a name="input_aks_system_node_pool"></a> [aks\_system\_node\_pool](#input\_aks\_system\_node\_pool) | The default (system) node pool, which autoscales between min\_count and max\_count.<br/>- name: 1-12 lowercase letters and digits, starting with a letter. Default "system".<br/>- vm\_size: required, e.g. "Standard\_D4ds\_v5".<br/>- min\_count, max\_count: 1-1000, min <= max. Defaults 2 and 5.<br/>- zones: availability zones, e.g. ["1", "2", "3"]. null uses no zones.<br/>- os\_disk\_type: "Managed" (default) or "Ephemeral", which needs a VM size with enough cache or temp disk.<br/>- only\_critical\_addons\_enabled: true taints the pool with CriticalAddonsOnly, so only system pods run<br/>  there; turn it on once aks\_user\_node\_pools can carry the workloads. Default false. Changing it<br/>  cycles the pool. | <pre>object({<br/>    name                         = optional(string, "system")<br/>    vm_size                      = string<br/>    min_count                    = optional(number, 2)<br/>    max_count                    = optional(number, 5)<br/>    zones                        = optional(list(string))<br/>    os_disk_type                 = optional(string, "Managed")<br/>    only_critical_addons_enabled = optional(bool, false)<br/>  })</pre> | n/a | yes |
| <a name="input_aks_tags"></a> [aks\_tags](#input\_aks\_tags) | Tags for the cluster, its system node pool and every user node pool. | `map(string)` | `{}` | no |
| <a name="input_aks_user_node_pools"></a> [aks\_user\_node\_pools](#input\_aks\_user\_node\_pools) | Linux user node pools for workloads, keyed by pool name (1-12 lowercase letters and digits, starting<br/>with a letter, not the system pool's name). Each pool autoscales. Default {}: no user pools.<br/>- vm\_size: required, e.g. "Standard\_D8ds\_v5".<br/>- min\_count, max\_count: required whole numbers, 0 <= min <= max <= 1000. 0 lets the pool scale to zero.<br/>- zones: e.g. ["1", "2", "3"]. null uses no zones.<br/>- os\_disk\_type: "Managed" (default) or "Ephemeral".<br/>- os\_sku: "AzureLinux", "AzureLinux3", "Ubuntu", "Ubuntu2204" or "Ubuntu2404". null uses Azure's default.<br/>- subnet\_id: a subnet in the same vnet as subnet\_id. null uses subnet\_id.<br/>- node\_labels: Kubernetes labels, e.g. { workload = "batch" }.<br/>- node\_taints: e.g. ["workload=batch:NoSchedule"]; effects NoSchedule, PreferNoSchedule or NoExecute.<br/>- spot: set to use Spot VMs, which Azure can evict at any time, e.g. {} or<br/>  { eviction\_policy = "Deallocate", max\_price = 0.05 }. eviction\_policy "Delete" (default) or<br/>  "Deallocate"; max\_price in USD per VM per hour, or -1 (default) for up to the on-demand price.<br/>  Spot pools also get the label and taint AKS puts on Spot nodes, so only pods that tolerate<br/>  kubernetes.azure.com/scalesetpriority=spot:NoSchedule run there. | <pre>map(object({<br/>    vm_size      = string<br/>    min_count    = number<br/>    max_count    = number<br/>    zones        = optional(list(string))<br/>    os_disk_type = optional(string, "Managed")<br/>    os_sku       = optional(string)<br/>    subnet_id    = optional(string)<br/>    node_labels  = optional(map(string), {})<br/>    node_taints  = optional(list(string), [])<br/>    spot = optional(object({<br/>      eviction_policy = optional(string, "Delete")<br/>      max_price       = optional(number, -1)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_aks_workload_identity_enabled"></a> [aks\_workload\_identity\_enabled](#input\_aks\_workload\_identity\_enabled) | Turn on workload identity and the OIDC issuer, so pods can use federated credentials. Once on, Azure doesn't allow turning the OIDC issuer off again. | `bool` | `false` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the cluster, e.g. module.rg.location. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the existing resource group the cluster is created in, e.g. module.rg.name. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the subnet the system node pool's nodes join, e.g. module.vnet.subnet\_ids["aks"]. With Azure CNI Overlay only nodes take addresses from it, not pods. | `string` | n/a | yes |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Entra ID tenant for cluster sign-in and Azure RBAC. null uses the tenant of the current subscription. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_aks_fqdn"></a> [aks\_fqdn](#output\_aks\_fqdn) | API server FQDN: the private FQDN for a private cluster (resolvable only from networks linked to its DNS zone), the public FQDN otherwise. |
| <a name="output_aks_id"></a> [aks\_id](#output\_aks\_id) | ID of the AKS cluster. |
| <a name="output_aks_identity_principal_id"></a> [aks\_identity\_principal\_id](#output\_aks\_identity\_principal\_id) | Principal ID of the cluster's system-assigned identity, for role assignments such as Network Contributor on the subnet. null with a user-assigned identity. |
| <a name="output_aks_kubelet_identity_object_id"></a> [aks\_kubelet\_identity\_object\_id](#output\_aks\_kubelet\_identity\_object\_id) | Object ID of the kubelet identity, for role assignments such as AcrPull or Key Vault access. |
| <a name="output_aks_name"></a> [aks\_name](#output\_aks\_name) | Name of the AKS cluster. |
| <a name="output_aks_node_resource_group"></a> [aks\_node\_resource\_group](#output\_aks\_node\_resource\_group) | Name of the resource group AKS created for the nodes and their load balancer. |
| <a name="output_aks_oidc_issuer_url"></a> [aks\_oidc\_issuer\_url](#output\_aks\_oidc\_issuer\_url) | OIDC issuer URL for federated credentials. null unless aks\_workload\_identity\_enabled is true. |
| <a name="output_aks_user_node_pool_ids"></a> [aks\_user\_node\_pool\_ids](#output\_aks\_user\_node\_pool\_ids) | Map of user node pool name to node pool ID. {} when there are none. |
<!-- END_TF_DOCS -->
