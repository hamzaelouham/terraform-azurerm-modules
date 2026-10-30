terraform {
  required_version = ">= 1.3"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0, < 6.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.0, < 3.0"
    }
  }
}
