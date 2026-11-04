output "aks_id" {
  description = "ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.aks.id
}

output "aks_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_fqdn" {
  description = "API server FQDN: the private FQDN for a private cluster (resolvable only from networks linked to its DNS zone), the public FQDN otherwise."
  value       = var.aks_private_cluster_enabled ? azurerm_kubernetes_cluster.aks.private_fqdn : azurerm_kubernetes_cluster.aks.fqdn
}

output "aks_node_resource_group" {
  description = "Name of the resource group AKS created for the nodes and their load balancer."
  value       = azurerm_kubernetes_cluster.aks.node_resource_group
}

output "aks_kubelet_identity_object_id" {
  description = "Object ID of the kubelet identity, for role assignments such as AcrPull or Key Vault access."
  value       = one(azurerm_kubernetes_cluster.aks.kubelet_identity[*].object_id)
}

output "aks_identity_principal_id" {
  description = "Principal ID of the cluster's system-assigned identity, for role assignments such as Network Contributor on the subnet. null with a user-assigned identity."
  value       = length(var.aks_identity_ids) > 0 ? null : azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for federated credentials. null unless aks_workload_identity_enabled is true."
  value       = var.aks_workload_identity_enabled ? azurerm_kubernetes_cluster.aks.oidc_issuer_url : null
}

output "aks_user_node_pool_ids" {
  description = "Map of user node pool name to node pool ID. {} when there are none."
  value       = { for name, pool in azurerm_kubernetes_cluster_node_pool.user : name => pool.id }
}
