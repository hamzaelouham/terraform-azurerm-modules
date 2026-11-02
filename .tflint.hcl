plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Reusable modules can't make prevent_destroy configurable, so it stays the caller's choice.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
