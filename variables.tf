variable "api_version" {
  description = "API version for Microsoft.Logic/workflows, without the '@' prefix. 2019-05-01 is the GA Consumption version; variablised so it is never pinned to a stale value."
  type        = string
  default     = "2019-05-01"

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}(-preview)?$", var.api_version))
    error_message = "api_version must be in the format YYYY-MM-DD or YYYY-MM-DD-preview."
  }
}

variable "diagnostics" {
  description = "Module-level default diagnostics: when set, every workflow gets an allLogs diagnostic setting to this workspace (named diag-<workflow>) unless it sets its own diagnostics or opts out with diagnostics_enabled = false. An object rather than a bare string so its presence stays plan-known when the workspace is created in the same apply (for_each keys must never depend on unknown values)."
  type = object({
    log_analytics_workspace_id = string
  })
  default = null
}

variable "diagnostics_api_version" {
  description = "API version for the Microsoft.Insights/diagnosticSettings extension resource, without the '@' prefix."
  type        = string
  default     = "2021-05-01-preview"

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}(-preview)?$", var.diagnostics_api_version))
    error_message = "diagnostics_api_version must be in the format YYYY-MM-DD or YYYY-MM-DD-preview."
  }
}

variable "location" {
  description = "Azure region for the workflows."
  type        = string
}

variable "resource_group_id" {
  description = "Resource id of the resource group the workflows deploy into (the azapi parent_id)."
  type        = string

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.resource_group_id))
    error_message = "resource_group_id must be a resource group resource id."
  }
}

variable "schema_validation_enabled" {
  description = "azapi schema validation for the resource body. Off by default: the workflow definition is free-form Workflow Definition Language that the embedded schema cannot usefully validate, and a lagging schema must never block a valid PUT."
  type        = bool
  default     = false
}

variable "shared_connections" {
  description = "API connections shared by every workflow in the call (the usual estate shape: the same Sentinel/Monitor/ITSM connections on every playbook), keyed by managed API name. Merged under each workflow's own connections (same-key workflow entries win); a workflow opts out with use_shared_connections = false."
  type = map(object({
    connection_id         = string
    connection_name       = optional(string)
    managed_api_id        = string
    managed_identity_auth = optional(bool, false)
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to the workflows (merged with per-workflow tags; the workflow's title always lands as the hidden-title tag)."
  type        = map(string)
  default     = {}
}

variable "workflows" {
  description = <<-EOT
    Consumption Logic App workflows (Microsoft.Logic/workflows) keyed by name
    (logic-ldo-uks-prd-001), each deployed WHOLE: one PUT carries the definition, the parameter
    values, the generated $connections parameter and the identity. Fields:
      title       REQUIRED human-readable description, becomes the hidden-title tag the portal
                  renders as the resource subtitle ("{Trigger type} - {what it does}").
      definition  REQUIRED, the complete workflow definition as a JSON STRING: the portal
                  code-view export, normally the output of templatefile(...) with scalar tokens
                  for the values Terraform owns. The module deploys it verbatim (jsondecode, no
                  reshaping), so the authored artefact IS the deployed artefact and a portal
                  export diffs cleanly against the template render. Parameter DECLARATIONS
                  (including $connections) live in the definition itself, exactly where the
                  portal exports them.
      parameters  Deployment VALUES for parameters the definition declares. Values are strings
                  (Terraform coerces numbers and bools, so value = 25 works; Object and Array
                  values pass jsonencode(...), the standard's rule for all workflow JSON); the
                  module converts them to their real JSON types. SecureString and SecureObject
                  values ride the provider's sensitive_body, so they never appear in the plan
                  output or the state's body.
      identity    SystemAssigned by default; UserAssigned supported.
      connections API connections for the workflow's managed connectors, keyed by the managed API
                  name the action bodies reference. Generates the entire $connections parameter
                  VALUE (connectionId, connectionName, id, and the ManagedServiceIdentity
                  authentication block when managed_identity_auth is true), so bodies keep saying
                  @parameters('$connections')['<api name>']['connectionId'] with zero hand-rolled
                  JSON. Consumption accepts ONLY V1 Microsoft.Web/connections; managed identity
                  auth needs parameterValueType "Alternative" on the connection plus this block.
      connections_identity_id  Names the user assigned identity (by resource id) inside every
                  managed identity authenticated connection's connectionProperties. REQUIRED when
                  the workflow runs as a user assigned identity: a bare authentication block means
                  SystemAssigned, and the platform rejects it
                  (InvalidWorkflowManagedIdentitySpecified) when no system identity exists.
      callback_trigger_name  When set, the module lists that trigger's callback URL (the SAS
                  invoke URL an action group receiver or external caller posts to) into the
                  callback_urls output. Must name a trigger the definition declares.
      diagnostics Optional per-workflow diagnostic setting (allLogs) to a Log Analytics workspace,
                  named diag-<workflow> unless overridden.
      access_control  IP restrictions for action/content/workflow_management, and for the trigger
                  additionally AAD open authentication policies (claims like iss/aud/appid), the
                  right way to let an action group or app call an HTTP trigger without shared
                  SAS exposure. Every policy MUST pin an aud claim (the platform rejects a policy
                  without one; validated here at plan time). Policies ADMIT token callers; SAS
                  stays valid alongside them unless trigger.sas_authentication_enabled = false
                  turns it off, at which point the policies are the only HTTP door.
                  DELIBERATE OMISSIONS from the full 2019-05-01 surface, each for cause:
                  integrationServiceEnvironment (the ISE is a retired Azure offering; none can
                  exist), openAuthenticationPolicies on the actions/contents/workflowManagement
                  sections (the type is shared in the spec but the platform applies OAuth policies
                  to trigger invocations only), and endpointsConfiguration (platform-populated
                  regional IP lists; read them from the workflows output).
      enabled, integration_account_id  Pass-throughs (enabled maps to properties.state).
      deploy_tier  0 (default), 1 or 2; each tier deploys after the ones below it. ARM validates a
                  native Workflow dispatch action's TARGET at PUT time (NestedWorkflowNotFound,
                  proven live), so a workflow that invokes a sibling by id deploys a tier above
                  that sibling: leaves are 0, their dispatchers are 1, and a dispatcher whose
                  target is itself a dispatcher (a router invoking a hooked handler, proven
                  needed live) is 2. Sibling references are CONSTRUCTED ARM ids, never this
                  module's outputs (that would be a dependency cycle).
      response_export_values, ignore_missing_property, ignore_null_property, ignore_casing
                  azapi passthroughs, defaulted for a stable diff (see deploy_tier and the
                  trimmed response_export_values default).
  EOT
  type = map(object({
    title   = string
    enabled = optional(bool, true)
    tags    = optional(map(string))

    definition = string

    identity = optional(object({
      type         = optional(string, "SystemAssigned")
      identity_ids = optional(set(string))
    }), {})

    parameters = optional(map(object({
      type  = string
      value = string
    })), {})

    connections_identity_id = optional(string)

    connections = optional(map(object({
      connection_id         = string
      connection_name       = optional(string)
      managed_api_id        = string
      managed_identity_auth = optional(bool, false)
    })), {})
    use_shared_connections = optional(bool, true)

    callback_trigger_name = optional(string)

    diagnostics = optional(object({
      log_analytics_workspace_id = string
      name                       = optional(string)
    }))
    diagnostics_enabled = optional(bool, true)

    access_control = optional(object({
      action_allowed_ips              = optional(list(string))
      content_allowed_ips             = optional(list(string))
      workflow_management_allowed_ips = optional(list(string))
      trigger = optional(object({
        allowed_ips = optional(list(string), [])
        open_authentication_policies = optional(map(object({
          claims = map(string)
        })), {})
        # SAS (shared access signature) authentication on the trigger's callback URL. Default true,
        # the platform default. false emits accessControl.triggers.sasAuthenticationPolicy
        # {state: Disabled}: the SAS URL stops authenticating and open authentication policies
        # carry the only HTTP door (native Workflow dispatch and managed-connector triggers do not
        # ride SAS). The property is ACCEPTED by the resource provider on api-version 2019-05-01
        # (proven against the ARM validate endpoint) although the published OpenAPI spec for that
        # version does not document it.
        sas_authentication_enabled = optional(bool, true)
      }))
    }))

    integration_account_id = optional(string)

    deploy_tier = optional(number, 0)

    # Trimmed by default, deliberately: ["*"] echoes the whole GET response including volatile
    # fields (changedTime and friends), which makes every plan show a no-op update-in-place on
    # every workflow (proven live). The default exports only the stable fields the module's
    # outputs read; widen it per workflow if you need more.
    response_export_values  = optional(list(string), ["identity", "properties.accessEndpoint", "properties.state", "properties.endpointsConfiguration"])
    ignore_missing_property = optional(bool, true)
    ignore_null_property    = optional(bool, true)
    ignore_casing           = optional(bool, true)
  }))
  default = {}

  validation {
    condition     = alltrue([for w in values(var.workflows) : length(trimspace(w.title)) > 0])
    error_message = "every workflow needs a non-empty title: it becomes the hidden-title tag the portal shows as the resource subtitle."
  }

  validation {
    condition     = alltrue([for w in values(var.workflows) : can(jsondecode(w.definition))])
    error_message = "definition must be valid JSON: pass the templatefile(...) or file(...) output of a portal-shaped workflow definition."
  }

  validation {
    condition = alltrue([
      for w in values(var.workflows) :
      try(alltrue([for k in ["$schema", "contentVersion", "triggers", "actions"] : contains(keys(jsondecode(w.definition)), k)]), false)
    ])
    error_message = "definition must be a complete workflow definition ($schema, contentVersion, triggers, actions): the portal code-view export always carries all four."
  }

  validation {
    condition = alltrue(flatten([
      for w in values(var.workflows) : [
        for p in values(w.parameters) : contains(["String", "SecureString", "Int", "Float", "Bool", "Object", "Array", "SecureObject"], p.type)
      ]
    ]))
    error_message = "parameter type must be one of String, SecureString, Int, Float, Bool, Object, Array, SecureObject."
  }

  validation {
    condition = alltrue(flatten([
      for w in values(var.workflows) : [
        for p in values(w.parameters) :
        contains(["Int", "Float"], p.type) ? can(tonumber(p.value)) : (
          p.type == "Bool" ? contains(["true", "false"], p.value) : (
            contains(["Object", "Array", "SecureObject"], p.type) ? can(jsondecode(p.value)) : true
          )
        )
      ]
    ]))
    error_message = "parameter values must match their declared type: numbers for Int/Float, \"true\"/\"false\" for Bool, and jsonencode(...) output for Object/Array/SecureObject."
  }

  validation {
    condition = alltrue(flatten([
      for w in values(var.workflows) : [
        for p_name in keys(w.parameters) : contains(try(keys(jsondecode(w.definition).parameters), []), p_name)
      ]
    ]))
    error_message = "every supplied parameter value must be DECLARED in the definition's parameters block: the definition is the contract, values only fill it."
  }

  validation {
    condition     = alltrue([for w in values(var.workflows) : !contains(keys(w.parameters), "$connections")])
    error_message = "do not supply the $connections parameter yourself: the connections map generates it."
  }

  validation {
    condition = alltrue([
      for w in values(var.workflows) :
      length(merge(w.use_shared_connections ? var.shared_connections : {}, w.connections)) == 0 ||
      contains(try(keys(jsondecode(w.definition).parameters), []), "$connections")
    ])
    error_message = "a workflow with connections needs the $connections parameter DECLARED in its definition (the portal export carries it); without the declaration the PUT is rejected."
  }

  validation {
    condition     = alltrue([for w in values(var.workflows) : contains(["SystemAssigned", "UserAssigned"], w.identity.type)])
    error_message = "identity.type must be SystemAssigned or UserAssigned (the workflow resource does not support both at once)."
  }

  validation {
    condition     = alltrue([for w in values(var.workflows) : w.identity.type != "UserAssigned" || try(length(w.identity.identity_ids) > 0, false)])
    error_message = "identity.type UserAssigned needs at least one identity id in identity.identity_ids."
  }

  validation {
    condition = alltrue([
      for w in values(var.workflows) :
      w.connections_identity_id != null ||
      !(w.identity.type == "UserAssigned" && anytrue([for c in values(merge(w.use_shared_connections ? var.shared_connections : {}, w.connections)) : c.managed_identity_auth]))
    ])
    error_message = "a UserAssigned workflow with managed identity authenticated connections needs connections_identity_id: a bare authentication block means SystemAssigned, which the workflow does not have."
  }

  validation {
    condition = alltrue([
      for w in values(var.workflows) :
      w.callback_trigger_name == null ||
      contains(try(keys(jsondecode(w.definition).triggers), []), coalesce(w.callback_trigger_name, "?"))
    ])
    error_message = "callback_trigger_name must name a trigger the definition declares."
  }

  validation {
    condition     = alltrue([for w in values(var.workflows) : contains([0, 1, 2], w.deploy_tier)])
    error_message = "deploy_tier must be 0 (default), 1 (deploys after tier 0; dispatches to leaves) or 2 (deploys after tiers 0 and 1; dispatches to tier-1 dispatchers)."
  }

  validation {
    condition = alltrue(flatten([
      for w in values(var.workflows) : [
        for pol in values(try(w.access_control.trigger.open_authentication_policies, {})) : contains(keys(pol.claims), "aud")
      ]
    ]))
    error_message = "every open authentication policy must pin an 'aud' claim: the platform REJECTS a policy without one (MissingOAuthRequiredClaimValue, proven live), so fail here at plan time instead."
  }
}
