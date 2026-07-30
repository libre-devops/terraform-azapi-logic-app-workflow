<!--
  Keep the title and badges OUTSIDE the centered <div>: the Terraform Registry's markdown renderer
  does not parse markdown inside an HTML block, so a # heading or [![badge]] in the div renders as
  literal text on the registry. Only the logo (HTML) goes in the div.
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="300">
    </picture>
  </a>
</div>

# Terraform AzAPI Logic App Workflow

Consumption Logic App workflows deployed WHOLE through azapi: one PUT carries the definition (the
portal code-view export, rendered by `templatefile`), the typed parameter values, the generated
`$connections` parameter and the identity, so the authored artefact IS the deployed artefact.

[![CI](https://github.com/libre-devops/terraform-azapi-logic-app-workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/libre-devops/terraform-azapi-logic-app-workflow/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/libre-devops/terraform-azapi-logic-app-workflow?sort=semver&label=release)](https://github.com/libre-devops/terraform-azapi-logic-app-workflow/releases/latest)
[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
[![License](https://img.shields.io/github/license/libre-devops/terraform-azapi-logic-app-workflow)](./LICENSE)

---

## Overview

This module is the **full-definition** way to run Consumption Logic Apps as code, built for the
portal-first workflow: develop in the designer, export the code view into a `.json.tftpl`
template, ctrl+F the values Terraform owns into `${tokens}`, and deploy the whole thing with
`templatefile(...)`. It sits beside
[`terraform-azurerm-logic-app-workflow`](https://github.com/libre-devops/terraform-azurerm-logic-app-workflow)
(the shell + per-resource authoring path, per the
[Libre DevOps Logic App standard](https://libredevops.org)) and deliberately trades that path's
granular resources for properties the per-resource split cannot give you:

- **One execution graph.** `runAfter` is the only ordering; there is no second `depends_on` graph
  across `azurerm_logic_app_trigger_*` / `azurerm_logic_app_action_*` resources to keep in
  lockstep, and no four-resources-per-playbook scatter.
- **The artefact is the portal export.** The definition deploys verbatim (decoded, never
  reshaped), so a portal export diffs cleanly against the rendered template: refactors are proven
  by byte-identical renders, and drift review is a JSON diff, not archaeology. All three shapes
  Azure hands you paste straight in (see [Authoring](#authoring-paste-it-straight-out-of-azure)).
- **Whole-workflow lifecycle.** Create, update and destroy PUT/DELETE the workflow itself. A
  concurrency-singleton trigger can never hit `CannotDisableTriggerConcurrency` (proven live: that
  trap only fires when a trigger is PATCHed out of a live definition individually).
- **Consumption connection facts, encoded.** Consumption accepts ONLY V1
  `Microsoft.Web/connections` (which also reject access policies); managed identity auth is the
  connection's `parameterValueType = "Alternative"` PLUS the
  `connectionProperties.authentication` block inside `$connections`, which the module generates
  from a typed map. Parameter DECLARATIONS (including `$connections`) stay in the definition,
  exactly where the portal exports them; the module supplies only the VALUES and validates the
  two halves against each other at plan time (undeclared values, missing `$connections`
  declarations and unknown callback triggers all fail the plan, not the run).
- **Sibling dispatch is ordered.** ARM validates a native `Workflow` dispatch action's TARGET at
  PUT time (`NestedWorkflowNotFound`, proven live), and sibling references must be CONSTRUCTED
  ARM ids (a module-output reference from a definition would be a dependency cycle). Mark a
  workflow that dispatches to a sibling with `deploy_tier = 1`, and one whose target is itself a
  dispatcher (a router invoking a hooked handler, proven needed live) with `deploy_tier = 2`;
  each tier deploys after the ones below it, in the same module call.
- **SAS can be turned off.** `trigger.sas_authentication_enabled = false` emits
  `sasAuthenticationPolicy: Disabled`: the callback URL stops authenticating and the AAD policies
  become the only HTTP door (native Workflow dispatch and connector triggers never used SAS). The
  property is accepted by the resource provider on 2019-05-01 (proven against the ARM validate
  endpoint) though absent from that version's published OpenAPI spec; a `check` flags SAS-off
  with no policy, since that trigger accepts no HTTP caller at all.
- **Plans stay quiet.** The default `response_export_values` is a trimmed stable set: `["*"]`
  echoes the whole GET response including volatile fields (`changedTime` and friends), which
  makes every plan a no-op update-in-place on every workflow (proven live). Widen it per
  workflow when you need more of the response.
- **Secrets stay out of state.** `SecureString` / `SecureObject` parameter values ride the
  provider's write-only `sensitive_body`, so they never appear in the plan output or the state's
  body. Rotation is detected by the provider's private-state hash; `sensitive_body_version` is
  deliberately not exposed, because its omit-unchanged-paths semantics would strip secure values
  from a full-resource PUT on unrelated updates.

The split between the two guard rails is evidence-based, not taste: anything the platform REJECTS
is a plan-time `validation` (a valueless parameter, a policy with no `aud` claim, connections with
no `$connections` declaration, a callback trigger that does not exist), each one confirmed against
the ARM validate endpoint rather than assumed. `checks` only warn, and only about things that
deploy cleanly and then bite later: an empty call, a definition with no trigger, a connection the
definition never references, a `$connections` declaration with nothing wired to it, and a trigger
with SAS off and no policy.

## Authoring: paste it straight out of Azure

`definition` takes the JSON in any of the three shapes Azure gives you, so there is nothing to
reshape by hand and no way to get the wrapping wrong:

| Copied from | Shape |
|---|---|
| Designer, Logic app code view | `{"definition": {...}, "parameters": {...}}` |
| `az rest`, `az logic workflow show`, Export template | `{"properties": {"definition": {...}, ...}, "id": ..., "name": ...}` |
| Another template in this shape | the bare definition, `{"$schema": ..., "triggers": ..., "actions": ...}` |

The module unwraps the outer two and deploys the definition inside; a workflow definition has no
top-level `definition` or `properties` key of its own, so the unwrap is unambiguous.

A wrapper's own `parameters` block is ADOPTED (4.4.0). It holds the SOURCE environment's VALUES,
and a portal export carries a value for every parameter its definition declares, so a paste
deploys untouched rather than failing on values the module could see and chose to discard. That
had been the one thing standing between "copy out of the portal" and "apply".

Precedence, lowest to highest: a `defaultValue` inside the definition, then whatever the wrapper
carried, then the `parameters` input, then the generated `$connections`. So naming a parameter in
`parameters` always overrides what arrived with the paste.

Two things are never adopted, each for cause:

- **`$connections`**, because the wrapper's copy names the source environment's connection
  resources. This module generates the whole value from the `connections` input instead.
- **`SecureString` and `SecureObject`**, because a secret someone typed into the designer would
  otherwise land in a template file, the plan output and the state's `body`. Secure values ride
  `sensitive_body`, so they stay an explicit input and a secure declaration carrying only a
  wrapper value is still rejected at plan.

A bare definition contributes nothing here: its top-level `parameters` is its DECLARATIONS, not
values, and reading those as values would make the check below vacuous.

Anything still without a value fails the PLAN rather than the apply, because the engine rejects a
valueless parameter outright (`InvalidTemplate`, "the value for the workflow parameter ... is not
provided"), and `$connections` left unwired trips a check.

The portal's read-back fields survive the round trip untouched: `evaluatedRecurrence` on a
Recurrence trigger deploys as pasted (accepted by the resource provider, proven against the ARM
validate endpoint), so there is nothing to hand-strip before committing the template.

So the round trip is: build it in the designer, open the code view, paste the whole thing into
`templates/<name>.json.tftpl`, ctrl+F the values Terraform owns into `${tokens}`, plan.

## Usage

```hcl
module "playbooks" {
  source  = "libre-devops/logic-app-workflow/azapi"
  version = "~> 4.0"

  resource_group_id = module.rg.ids["rg-ldo-uks-prd-001"]
  location          = "uksouth"
  tags              = module.tags.tags

  diagnostics = { log_analytics_workspace_id = module.law.workspace_ids["log-ldo-uks-prd-001"] }

  shared_connections = {
    "azuresentinel" = {
      connection_id         = module.api_connection.api_connection_ids["azuresentinel"]
      managed_api_id        = module.api_connection.api_connections["azuresentinel"].managed_api_id
      managed_identity_auth = true
    }
  }

  workflows = {
    "logic-ldo-uks-prd-001" = {
      title = "HTTP - Acknowledge a dispatch and comment on the Sentinel incident"

      definition = templatefile("${path.module}/templates/incident-ack.json.tftpl", {
        comment_prefix = var.comment_prefix
      })

      parameters = {
        comment_suffix     = { type = "String", value = "(automated acknowledgement)" }
        notify_webhook_url = { type = "SecureString", value = var.notify_webhook_url }
      }

      callback_trigger_name = "manual"
    }
  }
}
```

## Examples

- [`examples/minimal`](./examples/minimal) - one workflow from a portal-shaped template with a
  single scalar token: a daily Recurrence trigger and a Compose action.
- [`examples/complete`](./examples/complete) - the estate shape: a real V1 Sentinel connection
  with managed identity auth, typed parameters including a SecureString, diagnostics, an AAD open
  authentication policy on the trigger, and the callback URL output. Its second workflow is the
  paste-in path proven end to end: an unedited portal code view export, wrapper and all, with one
  ctrl+F token.

Consumption workflows are free at rest, so unlike this module's Security Copilot sibling the
examples are safe to apply and CI DOES live self-test them (apply then always destroy) on manual
dispatch.

## Developing

Local work needs **PowerShell 7+** and **[`just`](https://github.com/casey/just)**, because the recipes
wrap the [LibreDevOpsHelpers](https://www.powershellgallery.com/packages/LibreDevOpsHelpers)
PowerShell module (the same engine the `libre-devops/terraform-azure` action runs in CI). Install
just with `brew install just`, or `uv tool add rust-just` then `uv run just <recipe>`.

Run `just` to list recipes: `just update-ldo-pwsh`, `just validate`, `just scan`,
`just pwsh-analyze`, `just test`, and `just docs`. The `plan`/`apply`/`destroy` recipes run an
example against the remote state, and `just e2e [minimal|complete]` applies then always destroys
one. Releasing is also `just`: `just increment-release [patch|minor|major]` bumps, tags, and
publishes a GitHub release, and the Terraform Registry picks up the tag.

## Security scan exceptions

This module is scanned with [Trivy](https://github.com/aquasecurity/trivy); HIGH and CRITICAL
findings fail the build. Any waiver is a deliberate, reviewed decision, never a way to quiet a
finding that should be fixed. Waivers live in [`.trivyignore.yaml`](./.trivyignore.yaml) (the
machine-applied source of truth, passed to Trivy with `--ignorefile`) and are mirrored in the table
below so the reason is auditable.

| Trivy ID | Resource | Finding | Justification |
|----------|----------|---------|---------------|
| _None_   |          |         |               |

To add an exception: add an entry to `.trivyignore.yaml` (`id`, optional `paths` to scope it, and a
`statement` recording why), then add a matching row here. Both the file and this table are reviewed
in the pull request.

## Reference

The Requirements, Providers, Inputs, Outputs, and Resources below are generated by `terraform-docs`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.0, < 2.0.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.5.0, < 3.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | >= 2.5.0, < 3.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azapi_resource.diagnostics](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.last](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.late](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.this](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource_action.callback_url](https://registry.terraform.io/providers/Azure/azapi/latest/docs/data-sources/resource_action) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_api_version"></a> [api\_version](#input\_api\_version) | API version for Microsoft.Logic/workflows, without the '@' prefix. 2019-05-01 is the GA Consumption version; variablised so it is never pinned to a stale value. | `string` | `"2019-05-01"` | no |
| <a name="input_diagnostics"></a> [diagnostics](#input\_diagnostics) | Module-level default diagnostics: when set, every workflow gets an allLogs diagnostic setting to this workspace (named diag-<workflow>) unless it sets its own diagnostics or opts out with diagnostics\_enabled = false. An object rather than a bare string so its presence stays plan-known when the workspace is created in the same apply (for\_each keys must never depend on unknown values). | <pre>object({<br/>    log_analytics_workspace_id = string<br/>  })</pre> | `null` | no |
| <a name="input_diagnostics_api_version"></a> [diagnostics\_api\_version](#input\_diagnostics\_api\_version) | API version for the Microsoft.Insights/diagnosticSettings extension resource, without the '@' prefix. | `string` | `"2021-05-01-preview"` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the workflows. | `string` | n/a | yes |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource id of the resource group the workflows deploy into (the azapi parent\_id). | `string` | n/a | yes |
| <a name="input_schema_validation_enabled"></a> [schema\_validation\_enabled](#input\_schema\_validation\_enabled) | azapi schema validation for the resource body. Off by default: the workflow definition is free-form Workflow Definition Language that the embedded schema cannot usefully validate, and a lagging schema must never block a valid PUT. | `bool` | `false` | no |
| <a name="input_shared_connections"></a> [shared\_connections](#input\_shared\_connections) | API connections shared by every workflow in the call (the usual estate shape: the same Sentinel/Monitor/ITSM connections on every playbook), keyed by managed API name. Merged under each workflow's own connections (same-key workflow entries win); a workflow opts out with use\_shared\_connections = false. | <pre>map(object({<br/>    connection_id         = string<br/>    connection_name       = optional(string)<br/>    managed_api_id        = string<br/>    managed_identity_auth = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the workflows (merged with per-workflow tags; the workflow's title always lands as the hidden-title tag). | `map(string)` | `{}` | no |
| <a name="input_workflows"></a> [workflows](#input\_workflows) | Consumption Logic App workflows (Microsoft.Logic/workflows) keyed by name<br/>(logic-ldo-uks-prd-001), each deployed WHOLE: one PUT carries the definition, the parameter<br/>values, the generated $connections parameter and the identity. Fields:<br/>  title       REQUIRED human-readable description, becomes the hidden-title tag the portal<br/>              renders as the resource subtitle ("{Trigger type} - {what it does}").<br/>  definition  REQUIRED, the complete workflow definition as a JSON STRING: the portal<br/>              code-view export, normally the output of templatefile(...) with scalar tokens<br/>              for the values Terraform owns. The module deploys it verbatim (jsondecode, no<br/>              reshaping), so the authored artefact IS the deployed artefact and a portal<br/>              export diffs cleanly against the template render. Parameter DECLARATIONS<br/>              (including $connections) live in the definition itself, exactly where the<br/>              portal exports them.<br/>              THREE SHAPES ARE ACCEPTED, so anything you copy out of Azure pastes straight in:<br/>              the bare definition ({"$schema", "contentVersion", "triggers", "actions", ...}),<br/>              the portal code view, which wraps it as {"definition": {...}, "parameters": {...}},<br/>              and an ARM resource GET (az rest / az logic workflow show), which wraps it as<br/>              {"properties": {"definition": {...}, ...}, "id": ..., "name": ...}. The module<br/>              unwraps the outer two and deploys the definition inside.<br/>              A WRAPPER'S OWN parameters BLOCK IS IGNORED, deliberately: it holds the SOURCE<br/>              environment's VALUES (live connection ids, a resolved $connections block, maybe a<br/>              secret someone typed into the designer), and this module takes values from the<br/>              parameters and connections inputs so they stay environment-specific and secrets<br/>              stay out of the template. Re-supply anything you actually need: a declared<br/>              parameter left with no value and no defaultValue FAILS THE PLAN (the engine<br/>              rejects that deploy), and a $connections declaration with nothing wired to it<br/>              warns through a check (it deploys, then fails at run time).<br/>  parameters  Deployment VALUES for parameters the definition declares. Values are strings<br/>              (Terraform coerces numbers and bools, so value = 25 works; Object and Array<br/>              values pass jsonencode(...), the standard's rule for all workflow JSON); the<br/>              module converts them to their real JSON types. SecureString and SecureObject<br/>              values ride the provider's sensitive\_body, so they never appear in the plan<br/>              output or the state's body.<br/>  identity    SystemAssigned by default; UserAssigned supported.<br/>  connections API connections for the workflow's managed connectors, keyed by the managed API<br/>              name the action bodies reference. Generates the entire $connections parameter<br/>              VALUE (connectionId, connectionName, id, and the ManagedServiceIdentity<br/>              authentication block when managed\_identity\_auth is true), so bodies keep saying<br/>              @parameters('$connections')['<api name>']['connectionId'] with zero hand-rolled<br/>              JSON. Consumption accepts ONLY V1 Microsoft.Web/connections; managed identity<br/>              auth needs parameterValueType "Alternative" on the connection plus this block.<br/>  connections\_identity\_id  Names the user assigned identity (by resource id) inside every<br/>              managed identity authenticated connection's connectionProperties. REQUIRED when<br/>              the workflow runs as a user assigned identity: a bare authentication block means<br/>              SystemAssigned, and the platform rejects it<br/>              (InvalidWorkflowManagedIdentitySpecified) when no system identity exists.<br/>  callback\_trigger\_name  When set, the module lists that trigger's callback URL (the SAS<br/>              invoke URL an action group receiver or external caller posts to) into the<br/>              callback\_urls output. Must name a trigger the definition declares.<br/>  diagnostics Optional per-workflow diagnostic setting (allLogs) to a Log Analytics workspace,<br/>              named diag-<workflow> unless overridden.<br/>  access\_control  IP restrictions for action/content/workflow\_management, and for the trigger<br/>              additionally AAD open authentication policies (claims like iss/aud/appid), the<br/>              right way to let an action group or app call an HTTP trigger without shared<br/>              SAS exposure. Every policy MUST pin an aud claim (the platform rejects a policy<br/>              without one; validated here at plan time). Policies ADMIT token callers; SAS<br/>              stays valid alongside them unless trigger.sas\_authentication\_enabled = false<br/>              turns it off, at which point the policies are the only HTTP door.<br/>              DELIBERATE OMISSIONS from the full 2019-05-01 surface, each for cause:<br/>              integrationServiceEnvironment (the ISE is a retired Azure offering; none can<br/>              exist), openAuthenticationPolicies on the actions/contents/workflowManagement<br/>              sections (the type is shared in the spec but the platform applies OAuth policies<br/>              to trigger invocations only), and endpointsConfiguration (platform-populated<br/>              regional IP lists; read them from the workflows output).<br/>  enabled, integration\_account\_id  Pass-throughs (enabled maps to properties.state).<br/>  deploy\_tier  0 (default), 1 or 2; each tier deploys after the ones below it. ARM validates a<br/>              native Workflow dispatch action's TARGET at PUT time (NestedWorkflowNotFound,<br/>              proven live), so a workflow that invokes a sibling by id deploys a tier above<br/>              that sibling: leaves are 0, their dispatchers are 1, and a dispatcher whose<br/>              target is itself a dispatcher (a router invoking a hooked handler, proven<br/>              needed live) is 2. Sibling references are CONSTRUCTED ARM ids, never this<br/>              module's outputs (that would be a dependency cycle).<br/>  response\_export\_values, ignore\_missing\_property, ignore\_null\_property, ignore\_casing<br/>              azapi passthroughs, defaulted for a stable diff (see deploy\_tier and the<br/>              trimmed response\_export\_values default). | <pre>map(object({<br/>    title   = string<br/>    enabled = optional(bool, true)<br/>    tags    = optional(map(string))<br/><br/>    definition = string<br/><br/>    identity = optional(object({<br/>      type         = optional(string, "SystemAssigned")<br/>      identity_ids = optional(set(string))<br/>    }), {})<br/><br/>    parameters = optional(map(object({<br/>      type  = string<br/>      value = string<br/>    })), {})<br/><br/>    connections_identity_id = optional(string)<br/><br/>    connections = optional(map(object({<br/>      connection_id         = string<br/>      connection_name       = optional(string)<br/>      managed_api_id        = string<br/>      managed_identity_auth = optional(bool, false)<br/>    })), {})<br/>    use_shared_connections = optional(bool, true)<br/><br/>    callback_trigger_name = optional(string)<br/><br/>    diagnostics = optional(object({<br/>      log_analytics_workspace_id = string<br/>      name                       = optional(string)<br/>    }))<br/>    diagnostics_enabled = optional(bool, true)<br/><br/>    access_control = optional(object({<br/>      action_allowed_ips              = optional(list(string))<br/>      content_allowed_ips             = optional(list(string))<br/>      workflow_management_allowed_ips = optional(list(string))<br/>      trigger = optional(object({<br/>        allowed_ips = optional(list(string), [])<br/>        open_authentication_policies = optional(map(object({<br/>          claims = map(string)<br/>        })), {})<br/>        # SAS (shared access signature) authentication on the trigger's callback URL. Default true,<br/>        # the platform default. false emits accessControl.triggers.sasAuthenticationPolicy<br/>        # {state: Disabled}: the SAS URL stops authenticating and open authentication policies<br/>        # carry the only HTTP door (native Workflow dispatch and managed-connector triggers do not<br/>        # ride SAS). The property is ACCEPTED by the resource provider on api-version 2019-05-01<br/>        # (proven against the ARM validate endpoint) although the published OpenAPI spec for that<br/>        # version does not document it.<br/>        sas_authentication_enabled = optional(bool, true)<br/>      }))<br/>    }))<br/><br/>    integration_account_id = optional(string)<br/><br/>    deploy_tier = optional(number, 0)<br/><br/>    # Trimmed by default, deliberately: ["*"] echoes the whole GET response including volatile<br/>    # fields (changedTime and friends), which makes every plan show a no-op update-in-place on<br/>    # every workflow (proven live). The default exports only the stable fields the module's<br/>    # outputs read; widen it per workflow if you need more.<br/>    response_export_values  = optional(list(string), ["identity", "properties.accessEndpoint", "properties.state", "properties.endpointsConfiguration"])<br/>    ignore_missing_property = optional(bool, true)<br/>    ignore_null_property    = optional(bool, true)<br/>    ignore_casing           = optional(bool, true)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_endpoints"></a> [access\_endpoints](#output\_access\_endpoints) | Map of workflow name to its access endpoint (from the PUT response). |
| <a name="output_callback_urls"></a> [callback\_urls](#output\_callback\_urls) | Map of workflow name to its callback\_trigger\_name trigger's invoke URL (the SAS URL an action group receiver or external caller posts to). Sensitive: the SAS grants invoke. |
| <a name="output_diagnostic_setting_ids"></a> [diagnostic\_setting\_ids](#output\_diagnostic\_setting\_ids) | Map of workflow name to its diagnostic setting resource id (only workflows with diagnostics). |
| <a name="output_identities"></a> [identities](#output\_identities) | Map of workflow name to its identity { principal\_id, tenant\_id } (principal\_id is populated for system-assigned identities), for role assignments. |
| <a name="output_ids"></a> [ids](#output\_ids) | Map of workflow name to its resource id. |
| <a name="output_ids_zipmap"></a> [ids\_zipmap](#output\_ids\_zipmap) | Map of workflow name to a { name, id } object, for passing where both are needed together. |
| <a name="output_names"></a> [names](#output\_names) | The workflow names. |
| <a name="output_tags"></a> [tags](#output\_tags) | The base tags applied to the workflows. |
| <a name="output_workflows"></a> [workflows](#output\_workflows) | Map of workflow name to { id, name, location, state, and the raw exported properties } for anything the typed outputs do not surface (outbound IPs, endpoints configuration). |
<!-- END_TF_DOCS -->
