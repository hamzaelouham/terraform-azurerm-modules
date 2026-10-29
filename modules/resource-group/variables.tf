variable "name" {
  description = "Name of the resource group. 1-90 characters: letters, digits, '_', '-', '.', '(' and ')'; must not end with '.'."
  type        = string

  validation {
    condition     = can(regex("^[-\\w.()]{0,89}[-\\w()]$", var.name))
    error_message = "name must be 1-90 characters of letters, digits, '_', '-', '.', '(' or ')', and must not end with '.'."
  }
}

variable "location" {
  description = "Azure region for the resource group, e.g. \"westeurope\" or \"West Europe\". Normalized to the lowercase, no-space form."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9 ]+$", trimspace(var.location)))
    error_message = "location must be a non-empty Azure region name such as \"westeurope\" or \"West Europe\"."
  }
}

variable "tags" {
  description = "Tags to apply to the resource group."
  type        = map(string)
  default     = {}
  nullable    = false
}
