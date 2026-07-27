<!--
  Header for the complete example README. Edit this file, then run `just docs`
  (or ./Sort-LdoTerraform.ps1 -IncludeExamples) to regenerate the section between the markers.
  The example's main.tf is embedded into the README automatically (see .terraform-docs.yml).
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="200">
    </picture>
  </a>
</div>

# Complete example

The full estate shape: one playbook deployed whole from a portal-shaped template (scalar tokens
only), typed parameter values including a SecureString riding the provider's write-only
`sensitive_body`, the generated `$connections` parameter against a real V1 Sentinel connection
with managed identity auth (`parameterValueType = "Alternative"`, the only combination Consumption
accepts), diagnostics to a Log Analytics workspace, an AAD open authentication policy on the
trigger, and the trigger's callback URL surfaced for an action group receiver.

Everything here is free at rest (the workflow only bills per action execution and nothing invokes
it), so the example is safe to apply; `just e2e complete` applies then always destroys it, and the
CI self-test does the same on manual dispatch.

[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.0, < 2.0.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.5.0, < 3.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | 2.11.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.81.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_law"></a> [law](#module\_law) | libre-devops/log-analytics-workspace/azurerm | ~> 4.0 |
| <a name="module_logic_app_workflow"></a> [logic\_app\_workflow](#module\_logic\_app\_workflow) | ../../ | n/a |
| <a name="module_rg"></a> [rg](#module\_rg) | libre-devops/rg/azurerm | ~> 4.0 |
| <a name="module_tags"></a> [tags](#module\_tags) | libre-devops/tags/azurerm | ~> 4.0 |

## Resources

| Name | Type |
|------|------|
| [azapi_resource.sentinel_connection](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_managed_api.sentinel](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/managed_api) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_comment_prefix"></a> [comment\_prefix](#input\_comment\_prefix) | Prefix for the acknowledgement comment, substituted into the workflow template by templatefile (the ctrl+F contract). | `string` | `"SOC automation"` | no |
| <a name="input_deployed_branch"></a> [deployed\_branch](#input\_deployed\_branch) | Git branch the deployment came from. Auto-filled in CI from TF\_VAR\_deployed\_branch. | `string` | `""` | no |
| <a name="input_deployed_repo"></a> [deployed\_repo](#input\_deployed\_repo) | Repository URL the deployment came from. Auto-filled in CI from TF\_VAR\_deployed\_repo. | `string` | `""` | no |
| <a name="input_loc"></a> [loc](#input\_loc) | Outfix: short Azure region code used in resource names (for example uks). | `string` | `"uks"` | no |
| <a name="input_notify_webhook_url"></a> [notify\_webhook\_url](#input\_notify\_webhook\_url) | Webhook the summary is POSTed to; a SecureString workflow parameter riding sensitive\_body. The example.com default fails deterministically on purpose, so a drill exercises the failure path without a third-party dependency. | `string` | `"https://example.com/soc-notify"` | no |
| <a name="input_regions"></a> [regions](#input\_regions) | Map of short region codes to Azure region slugs. | `map(string)` | <pre>{<br/>  "eus": "eastus",<br/>  "euw": "westeurope",<br/>  "uks": "uksouth",<br/>  "ukw": "ukwest"<br/>}</pre> | no |
| <a name="input_short"></a> [short](#input\_short) | Infix: short product code used in resource names. | `string` | `"ldo"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_endpoints"></a> [access\_endpoints](#output\_access\_endpoints) | The workflow access endpoints. |
| <a name="output_callback_urls"></a> [callback\_urls](#output\_callback\_urls) | The manual trigger's invoke URL, for an action group receiver. Sensitive: the SAS grants invoke. |
| <a name="output_diagnostic_setting_ids"></a> [diagnostic\_setting\_ids](#output\_diagnostic\_setting\_ids) | The diagnostic setting ids. |
| <a name="output_identities"></a> [identities](#output\_identities) | The workflow identities (principal and tenant ids), for role assignments. |
| <a name="output_ids"></a> [ids](#output\_ids) | The workflow resource ids. |
<!-- END_TF_DOCS -->
