resource "azurerm_resource_group" "rg" {
  name     = var.name
  location = lower(replace(var.location, " ", ""))
  tags     = var.rg_tags


  lifecycle {
    prevent_destroy = true
  }
}
