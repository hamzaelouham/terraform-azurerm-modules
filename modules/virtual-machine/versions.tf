terraform {
  required_version = ">= 1.17"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 5.12 is the version this module's arguments were checked against.
      version = ">= 5.12, < 6.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.0, < 3.0"
    }
  }
}
