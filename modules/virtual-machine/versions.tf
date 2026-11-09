terraform {
  required_version = ">= 1.17"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 5.12 is the oldest azurerm with everything this module uses.
      version = ">= 5.12, < 6.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.0, < 3.0"
    }
  }
}
