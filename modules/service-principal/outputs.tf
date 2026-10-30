output "client_id" {
  description = "Client (application) ID, used to sign in as the service principal."
  value       = azuread_application.app.client_id
}

output "object_id" {
  description = "Object ID of the service principal, for role assignments (azurerm_role_assignment.principal_id) and key vault access policies."
  value       = azuread_service_principal.sp.object_id
}

output "application_object_id" {
  description = "Object ID of the application registration."
  value       = azuread_application.app.object_id
}

output "application_id" {
  description = "Resource ID of the application (/applications/<object id>), for adding further credentials outside this module."
  value       = azuread_application.app.id
}

output "tenant_id" {
  description = "Tenant ID of the service principal."
  value       = azuread_service_principal.sp.application_tenant_id
}

output "client_secret" {
  description = "Client secret, or null when sp_create_password is false."
  value       = one(azuread_application_password.password[*].value)
  sensitive   = true
}

output "client_secret_end_date" {
  description = "Expiry of the client secret, or null when sp_create_password is false."
  value       = one(azuread_application_password.password[*].end_date)
}
