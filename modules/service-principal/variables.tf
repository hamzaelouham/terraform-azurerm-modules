variable "sp_display_name" {
  description = "Display name of the Entra ID application and its service principal, e.g. \"sp-terraform-dev\"."
  type        = string

  validation {
    condition     = length(trimspace(var.sp_display_name)) > 0 && length(var.sp_display_name) <= 120
    error_message = "sp_display_name must be 1-120 characters and not blank."
  }
}

variable "sp_description" {
  description = "Description of the application and service principal."
  type        = string
  default     = null
}

variable "sp_notes" {
  description = "Free-text notes on the application and service principal, e.g. owning team or purpose."
  type        = string
  default     = null
}

variable "sp_owners" {
  description = "Additional owner object IDs. The identity running Terraform is always added as an owner."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for id in var.sp_owners : can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", id))])
    error_message = "sp_owners must contain object IDs (GUIDs)."
  }
}

variable "sp_tags" {
  description = "Tags (plain strings) to apply to the application."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "sp_prevent_duplicate_names" {
  description = "Fail instead of creating the application when another application already has the same display name."
  type        = bool
  default     = true
  nullable    = false
}

variable "sp_app_role_assignment_required" {
  description = "Require users and apps to be assigned an app role before they can get tokens for this application."
  type        = bool
  default     = false
  nullable    = false
}

variable "sp_enterprise_app" {
  description = "List the service principal under Enterprise applications in the Entra admin center."
  type        = bool
  default     = true
  nullable    = false
}

variable "sp_federated_credentials" {
  description = <<-EOT
    OIDC federated credentials keyed by display name, for secretless sign-in from CI. Examples:
      GitHub Actions: issuer = "https://token.actions.githubusercontent.com", subject = "repo:<org>/<repo>:ref:refs/heads/main"
      GitLab CI:      issuer = "https://gitlab.com", subject = "project_path:<group>/<project>:ref_type:branch:ref:main"
      Azure DevOps:   issuer and subject come from the service connection's workload identity federation details.
  EOT
  type = map(object({
    issuer      = string
    subject     = string
    audiences   = optional(list(string), ["api://AzureADTokenExchange"])
    description = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for cred in var.sp_federated_credentials : can(regex("^https://", cred.issuer)) && length(trimspace(cred.subject)) > 0 && length(cred.audiences) > 0])
    error_message = "Each sp_federated_credentials entry needs an https:// issuer, a non-blank subject and at least one audience."
  }

  validation {
    condition     = alltrue([for name in keys(var.sp_federated_credentials) : can(regex("^[A-Za-z0-9][-\\w.]{0,119}$", name))])
    error_message = "sp_federated_credentials keys must be 1-120 characters of letters, digits, '_', '-' or '.', starting with a letter or digit."
  }
}

variable "sp_create_password" {
  description = "Create a client secret. Prefer sp_federated_credentials where the CI system supports OIDC."
  type        = bool
  default     = false
  nullable    = false
}

variable "sp_password_rotation_days" {
  description = "Days after which the next apply replaces the client secret."
  type        = number
  default     = 90
  nullable    = false

  validation {
    condition     = floor(var.sp_password_rotation_days) == var.sp_password_rotation_days && var.sp_password_rotation_days >= 1 && var.sp_password_rotation_days <= 365
    error_message = "sp_password_rotation_days must be a whole number between 1 and 365."
  }
}

variable "sp_password_expiry_grace_days" {
  description = "Days the client secret stays valid after its rotation date, in case the next apply runs late."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = floor(var.sp_password_expiry_grace_days) == var.sp_password_expiry_grace_days && var.sp_password_expiry_grace_days >= 0 && var.sp_password_expiry_grace_days <= 365
    error_message = "sp_password_expiry_grace_days must be a whole number between 0 and 365."
  }
}
