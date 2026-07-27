provider "azurerm" {
  features {
    # A workspace left soft-deleted blocks name reuse for 14 days; the self-test applies and
    # destroys the same names every run, so destroy must purge.
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }

  storage_use_azuread = true
  use_oidc            = true
}

# azapi authenticates from the ambient Azure context (ARM_* in CI, az CLI locally).
provider "azapi" {
  use_oidc = true
}
