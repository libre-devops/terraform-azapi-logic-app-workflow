# Consumption Logic App workflows deployed WHOLE through azapi: one PUT carries the definition
# (the portal code-view export, normally rendered by templatefile), the workflow parameter values,
# the generated $connections parameter and the identity, so the authored artefact IS the deployed
# artefact. Design facts this module encodes (all proven live in the Libre DevOps SOC estate):
#   - runAfter is the only execution graph. There is no per-trigger/per-action resource split, so
#     no second depends_on graph to keep in lockstep with it and no four-resources-per-playbook
#     scatter.
#   - Lifecycle is whole-workflow: create, update and destroy PUT/DELETE the workflow itself. A
#     concurrency-singleton trigger can therefore never hit CannotDisableTriggerConcurrency; that
#     trap only exists when a trigger is PATCHed out of a live definition individually.
#   - Consumption accepts ONLY V1 Microsoft.Web/connections (V1 connections also reject access
#     policies). Managed identity auth on a managed connector is the connection's
#     parameterValueType "Alternative" PLUS the connectionProperties.authentication block inside
#     the $connections parameter value, which this module generates.
locals {
  # Decoded once; the definition deploys verbatim (no reshaping), so a portal export diffs
  # cleanly against the rendered template.
  definitions = { for k, w in var.workflows : k => jsondecode(w.definition) }

  # Effective connections: the shared estate set merged under each workflow's own (same-key
  # workflow entries win); a workflow with use_shared_connections = false keeps only its own.
  effective_connections = {
    for k, w in var.workflows : k => merge(
      w.use_shared_connections ? var.shared_connections : {},
      w.connections,
    )
  }

  # The $connections parameter VALUE, the shape managed connector action bodies reference as
  # @parameters('$connections')['<api name>']['connectionId']. The DECLARATION stays in the
  # definition, exactly where the portal exports it.
  connections_parameter_value = {
    for k, w in var.workflows : k => {
      for api_name, c in local.effective_connections[k] : api_name => merge(
        {
          connectionId   = c.connection_id
          connectionName = coalesce(c.connection_name, api_name)
          id             = c.managed_api_id
        },
        c.managed_identity_auth ? {
          connectionProperties = {
            authentication = merge(
              { type = "ManagedServiceIdentity" },
              w.connections_identity_id != null ? { identity = w.connections_identity_id } : {},
            )
          }
        } : {},
      )
    } if length(local.effective_connections[k]) > 0
  }

  # Parameter values arrive as strings (the input convention shared with the azurerm shell
  # module) and are converted here to the real JSON types the ARM parameters block carries.
  # One homogeneous sub-map per declared type, merged: a single ternary chain would mix result
  # types (object vs string) and fail Terraform's conditional type unification.
  # Secure values are split out to ride sensitive_body, so they never sit in the plan output or
  # the state's body attribute.
  parameter_values = {
    for k, w in var.workflows : k => merge(
      { for p_name, p in w.parameters : p_name => { value = p.value } if p.type == "String" },
      { for p_name, p in w.parameters : p_name => { value = tonumber(p.value) } if contains(["Int", "Float"], p.type) },
      { for p_name, p in w.parameters : p_name => { value = p.value == "true" } if p.type == "Bool" },
      { for p_name, p in w.parameters : p_name => { value = jsondecode(p.value) } if contains(["Object", "Array"], p.type) },
    )
  }

  secure_parameter_values = {
    for k, w in var.workflows : k => merge(
      { for p_name, p in w.parameters : p_name => { value = p.value } if p.type == "SecureString" },
      { for p_name, p in w.parameters : p_name => { value = jsondecode(p.value) } if p.type == "SecureObject" },
    )
  }

  workflow_parameters = {
    for k, w in var.workflows : k => merge(
      local.parameter_values[k],
      contains(keys(local.connections_parameter_value), k) ? { "$connections" = { value = local.connections_parameter_value[k] } } : {},
    )
  }

  # properties.accessControl, mapped from the same input shape the azurerm shell module takes.
  access_control = {
    for k, w in var.workflows : k => w.access_control == null ? null : merge(
      w.access_control.action_allowed_ips != null ? {
        actions = { allowedCallerIpAddresses = [for ip in coalesce(w.access_control.action_allowed_ips, []) : { addressRange = ip }] }
      } : {},
      w.access_control.content_allowed_ips != null ? {
        contents = { allowedCallerIpAddresses = [for ip in coalesce(w.access_control.content_allowed_ips, []) : { addressRange = ip }] }
      } : {},
      w.access_control.workflow_management_allowed_ips != null ? {
        workflowManagement = { allowedCallerIpAddresses = [for ip in coalesce(w.access_control.workflow_management_allowed_ips, []) : { addressRange = ip }] }
      } : {},
      w.access_control.trigger != null ? {
        triggers = merge(
          { allowedCallerIpAddresses = [for ip in try(w.access_control.trigger.allowed_ips, []) : { addressRange = ip }] },
          length(try(w.access_control.trigger.open_authentication_policies, {})) > 0 ? {
            openAuthenticationPolicies = {
              policies = {
                for pol_name, pol in w.access_control.trigger.open_authentication_policies : pol_name => {
                  type   = "AAD"
                  claims = [for c_name, c_value in pol.claims : { name = c_name, value = c_value }]
                }
              }
            }
          } : {},
        )
      } : {},
    )
  }
}

resource "azapi_resource" "this" {
  for_each = var.workflows

  type      = "Microsoft.Logic/workflows@${var.api_version}"
  name      = each.key
  parent_id = var.resource_group_id
  location  = var.location
  # The title is not optional furniture: hidden-title is what the portal renders as the subtitle,
  # and the standard requires it on every Logic App.
  tags = merge(var.tags, coalesce(each.value.tags, {}), { "hidden-title" = each.value.title })

  schema_validation_enabled = var.schema_validation_enabled

  response_export_values  = each.value.response_export_values
  ignore_missing_property = each.value.ignore_missing_property
  ignore_null_property    = each.value.ignore_null_property
  ignore_casing           = each.value.ignore_casing

  identity {
    type         = each.value.identity.type
    identity_ids = each.value.identity.type == "UserAssigned" ? tolist(each.value.identity.identity_ids) : null
  }

  body = {
    properties = merge(
      {
        state      = each.value.enabled ? "Enabled" : "Disabled"
        definition = local.definitions[each.key]
      },
      length(local.workflow_parameters[each.key]) > 0 ? { parameters = local.workflow_parameters[each.key] } : {},
      each.value.integration_account_id != null ? { integrationAccount = { id = each.value.integration_account_id } } : {},
      each.value.access_control != null ? { accessControl = local.access_control[each.key] } : {},
    )
  }

  # Secure parameter values are merge-patched into the PUT at request time and never appear in
  # the plan output or the state's body. sensitive_body_version is deliberately NOT exposed:
  # workflows update by FULL PUT, and the version map's semantics omit unchanged-version paths
  # from the request, which would strip the secure parameter values off the workflow on every
  # unrelated update. Without a version map the provider hashes the value into private state, so
  # a rotated secret is still detected and the full sensitive_body rides every create and update
  # (verified against the provider source, unmarshalSensitiveBody / ephemeralBodyChangeInPlan).
  sensitive_body = length(local.secure_parameter_values[each.key]) > 0 ? {
    properties = { parameters = local.secure_parameter_values[each.key] }
  } : null
}

# The per-workflow diagnostic setting (allLogs to Log Analytics) every production playbook
# carries; named diag-<workflow> per the naming convention unless overridden. Driven through
# azapi so the module needs no second provider.
resource "azapi_resource" "diagnostics" {
  # The filter checks OBJECT presence (plan-known), never the workspace id value (unknown when
  # the workspace is created in the same apply): for_each keys must stay plan-known.
  for_each = {
    for k, w in var.workflows : k => (
      w.diagnostics != null ? w.diagnostics : { log_analytics_workspace_id = var.diagnostics.log_analytics_workspace_id, name = null }
    ) if w.diagnostics_enabled && (w.diagnostics != null || var.diagnostics != null)
  }

  type      = "Microsoft.Insights/diagnosticSettings@${var.diagnostics_api_version}"
  name      = coalesce(each.value.name, "diag-${each.key}")
  parent_id = azapi_resource.this[each.key].id

  schema_validation_enabled = var.schema_validation_enabled

  body = {
    properties = {
      workspaceId = each.value.log_analytics_workspace_id
      logs = [
        {
          categoryGroup = "allLogs"
          enabled       = true
        }
      ]
    }
  }
}

# The invoke URL (SAS) of the named trigger, for action group receivers and external callers.
# listCallbackUrl is a POST data-plane-shaped action on the management API, so it is a data
# source, refreshed on every plan.
data "azapi_resource_action" "callback_url" {
  for_each = { for k, w in var.workflows : k => w.callback_trigger_name if w.callback_trigger_name != null }

  type        = "Microsoft.Logic/workflows/triggers@${var.api_version}"
  resource_id = "${azapi_resource.this[each.key].id}/triggers/${each.value}"
  action      = "listCallbackUrl"
  method      = "POST"

  response_export_values = ["*"]
}
