variable "resource_group_name" {
  description = "Name of an existing resource group to deploy into, e.g. module.rg.name."
  type        = string
}

variable "location" {
  description = "Azure region, normally the resource group's: module.rg.location."
  type        = string
}

variable "vnet_name" {
  description = "Name of the virtual network. 2-64 characters: letters, digits, '_', '-' and '.'; must start with a letter or digit and end with a letter, digit or '_'."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][-\\w.]{0,62}\\w$", var.vnet_name))
    error_message = "vnet_name must be 2-64 characters of letters, digits, '_', '-' or '.', start with a letter or digit, and end with a letter, digit or '_'."
  }
}

variable "vnet_address_space" {
  description = "Address space (CIDR blocks) for the virtual network."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.vnet_address_space) > 0 && alltrue([for cidr in var.vnet_address_space : can(cidrhost(cidr, 0))])
    error_message = "vnet_address_space must contain at least one valid CIDR block, e.g. \"10.0.0.0/16\"."
  }
}

variable "vnet_dns_servers" {
  description = "Custom DNS server IPs for the virtual network. Empty uses Azure-provided DNS."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for ip in var.vnet_dns_servers : can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", ip)) && can(cidrhost("${ip}/32", 0))])
    error_message = "vnet_dns_servers must contain valid IPv4 addresses."
  }
}

variable "vnet_tags" {
  description = "Tags to apply to the virtual network."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "subnets" {
  description = "Subnets to create, keyed by subnet name. Each subnet's address_prefixes must fall inside vnet_address_space."
  type = map(object({
    address_prefixes  = list(string)
    service_endpoints = optional(list(string), [])
    associate_nsg     = optional(bool, true)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for name in keys(var.subnets) : can(regex("^[A-Za-z0-9]([-\\w.]{0,78}\\w)?$", name))])
    error_message = "Subnet names must be 1-80 characters of letters, digits, '_', '-' or '.', start with a letter or digit, and end with a letter, digit or '_'."
  }

  validation {
    condition = alltrue(flatten([
      for subnet in var.subnets : concat(
        [length(subnet.address_prefixes) > 0],
        [for cidr in subnet.address_prefixes : can(cidrhost(cidr, 0))]
      )
    ]))
    error_message = "Every subnet needs at least one address_prefixes entry, and each must be a valid CIDR block, e.g. \"10.0.1.0/24\"."
  }
}

variable "nsg_name" {
  description = "Name of the network security group. 1-80 characters: letters, digits, '_', '-' and '.'; must start with a letter or digit and end with a letter, digit or '_'."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]([-\\w.]{0,78}\\w)?$", var.nsg_name))
    error_message = "nsg_name must be 1-80 characters of letters, digits, '_', '-' or '.', start with a letter or digit, and end with a letter, digit or '_'."
  }
}

variable "nsg_tags" {
  description = "Tags to apply to the network security group."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "nsg_rules" {
  description = "Security rules for the network security group, keyed by rule name."
  type = map(object({
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = string
    source_port_range          = optional(string, "*")
    destination_port_range     = string
    source_address_prefix      = string
    destination_address_prefix = optional(string, "*")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for rule in var.nsg_rules : floor(rule.priority) == rule.priority && rule.priority >= 100 && rule.priority <= 4096])
    error_message = "nsg_rules priority must be a whole number between 100 and 4096."
  }

  validation {
    condition     = length(distinct([for rule in var.nsg_rules : "${rule.direction}/${rule.priority}"])) == length(var.nsg_rules)
    error_message = "nsg_rules priorities must be unique per direction."
  }

  validation {
    condition     = alltrue([for rule in var.nsg_rules : contains(["Inbound", "Outbound"], rule.direction) && contains(["Allow", "Deny"], rule.access)])
    error_message = "nsg_rules direction must be \"Inbound\" or \"Outbound\", and access must be \"Allow\" or \"Deny\"."
  }

  validation {
    condition     = alltrue([for rule in var.nsg_rules : contains(["Tcp", "Udp", "Icmp", "Esp", "Ah", "*"], rule.protocol)])
    error_message = "nsg_rules protocol must be one of Tcp, Udp, Icmp, Esp, Ah or \"*\"."
  }
}
