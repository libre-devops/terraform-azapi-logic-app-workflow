provider "azurerm" {
  features {}

  storage_use_azuread = true
  use_oidc            = true
}

# azapi authenticates from the ambient Azure context (ARM_* in CI, az CLI locally).
provider "azapi" {
  use_oidc = true
}
