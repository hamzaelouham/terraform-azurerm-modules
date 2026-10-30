data "azuread_client_config" "current" {}

locals {
  # The deploying identity always stays an owner, so it can keep managing the app.
  owners = distinct(concat([data.azuread_client_config.current.object_id], var.sp_owners))
}

resource "azuread_application" "app" {
  display_name            = var.sp_display_name
  description             = var.sp_description
  notes                   = var.sp_notes
  owners                  = local.owners
  tags                    = var.sp_tags
  prevent_duplicate_names = var.sp_prevent_duplicate_names
}

resource "azuread_service_principal" "sp" {
  client_id                    = azuread_application.app.client_id
  description                  = var.sp_description
  notes                        = var.sp_notes
  owners                       = local.owners
  app_role_assignment_required = var.sp_app_role_assignment_required

  feature_tags {
    enterprise = var.sp_enterprise_app
    gallery    = false
  }
}

resource "azuread_application_federated_identity_credential" "federated" {
  for_each = var.sp_federated_credentials

  application_id = azuread_application.app.id
  display_name   = each.key
  description    = each.value.description
  issuer         = each.value.issuer
  subject        = each.value.subject
  audiences      = each.value.audiences
}

resource "time_rotating" "password" {
  count = var.sp_create_password ? 1 : 0

  rotation_days = var.sp_password_rotation_days
}

resource "azuread_application_password" "password" {
  count = var.sp_create_password ? 1 : 0

  application_id = azuread_application.app.id
  display_name   = "terraform-managed"
  # The secret stays valid for a grace period past its rotation date, so an
  # apply that runs a little late still finds the old secret working.
  end_date = timeadd(time_rotating.password[0].rotation_rfc3339, "${var.sp_password_expiry_grace_days * 24}h")

  rotate_when_changed = {
    rotation = time_rotating.password[0].id
  }
}
