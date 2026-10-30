resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
  dns_servers         = var.vnet_dns_servers
  tags                = var.vnet_tags
}

resource "azurerm_subnet" "subnet" {
  for_each = var.subnets

  name                 = each.key
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = each.value.address_prefixes

  dynamic "service_endpoint" {
    for_each = each.value.service_endpoints
    content {
      service = service_endpoint.value
    }
  }

  lifecycle {
    # A prefix is inside a block when it is at least as narrow and has the same
    # network address once masked to the block's prefix length.
    precondition {
      condition = alltrue([
        for prefix in each.value.address_prefixes : anytrue([
          for space in var.vnet_address_space : try(
            tonumber(split("/", prefix)[1]) >= tonumber(split("/", space)[1]) &&
            cidrhost("${split("/", prefix)[0]}/${split("/", space)[1]}", 0) == cidrhost(space, 0),
            false
          )
        ])
      ])
      error_message = "Subnet ${each.key}: every address_prefixes entry must fall inside vnet_address_space."
    }
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = var.nsg_name
  location            = azurerm_virtual_network.vnet.location
  resource_group_name = var.resource_group_name
  tags                = var.nsg_tags
}

resource "azurerm_network_security_rule" "rule" {
  for_each = var.nsg_rules

  name                        = each.key
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.nsg.name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefix       = each.value.source_address_prefix
  destination_address_prefix  = each.value.destination_address_prefix
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  for_each = { for name, subnet in var.subnets : name => subnet if subnet.associate_nsg }

  subnet_id                 = azurerm_subnet.subnet[each.key].id
  network_security_group_id = azurerm_network_security_group.nsg.id
}
