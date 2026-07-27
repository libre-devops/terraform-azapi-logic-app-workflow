terraform {
  # 1.11 floor: secure parameter values ride the provider's write-only sensitive_body, and
  # write-only attributes only exist from Terraform 1.11.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    azapi = {
      source = "Azure/azapi"
      # 2.5.0 floor, verified against the published provider schemas: sensitive_body needs 2.4.0
      # and ignore_null_property needs 2.5.0.
      version = ">= 2.5.0, < 3.0.0"
    }
  }
}
