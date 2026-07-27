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
  by byte-identical renders, and drift review is a JSON diff, not archaeology.
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

`checks` warn (never block) on the sharp edges: an empty call, a definition with no trigger, a
connection the definition never references, and a declared parameter with neither a value nor a
default (the class of error that otherwise surfaces at RUN time).

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
  authentication policy on the trigger, and the callback URL output.

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
