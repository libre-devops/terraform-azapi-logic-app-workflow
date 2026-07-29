locals {
  location   = lookup(var.regions, var.loc, "uksouth")
  rg_name    = "rg-${var.short}-${var.loc}-${terraform.workspace}-002"
  law_name   = "log-${var.short}-${var.loc}-${terraform.workspace}-002"
  logic_name = "logic-${var.short}-${var.loc}-${terraform.workspace}-02"
  paste_name = "logic-${var.short}-${var.loc}-${terraform.workspace}-03"
  conn_name  = "conn-sentinel-${var.short}-${var.loc}-${terraform.workspace}-02"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
  additional_tags = { Application = "terraform-azapi-logic-app-workflow" }
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

# Diagnostics destination. Not Sentinel-onboarded (nothing here needs it); still soft-deleted on
# destroy, so the provider features block purges it for clean name reuse between self-tests.
module "law" {
  source  = "libre-devops/log-analytics-workspace/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  log_analytics_workspaces = {
    (local.law_name) = {}
  }
}

# The estate-shaped Sentinel API connection, created the standard's way: azapi on
# Microsoft.Web/connections with parameterValueType "Alternative" for managed identity auth.
# Proven live both ways: V1 connections reject access policies (InvalidApiConnectionAccessPolicy)
# and Consumption workflows reject V2 connections (WorkflowInvalidApiConnectionV2), so on
# Consumption there is NO access policy resource at all; managed identity auth flows through
# "Alternative" plus the $connections connectionProperties block the module generates.
data "azurerm_managed_api" "sentinel" {
  name     = "azuresentinel"
  location = local.location
}

resource "azapi_resource" "sentinel_connection" {
  type                      = "Microsoft.Web/connections@2016-06-01"
  name                      = local.conn_name
  parent_id                 = module.rg.ids[local.rg_name]
  location                  = local.location
  tags                      = module.tags.tags
  schema_validation_enabled = false

  body = {
    properties = {
      displayName        = local.conn_name
      parameterValueType = "Alternative"
      api = {
        id = data.azurerm_managed_api.sentinel.id
      }
    }
  }
}

# The tenant, for the trigger's AAD open authentication policy below.
data "azurerm_client_config" "current" {}

# The complete shape: one workflow deployed WHOLE from a portal-shaped template (scalar tokens
# only), typed parameter values including a SecureString riding sensitive_body, the generated
# $connections parameter with managed identity auth, diagnostics to the workspace, the trigger
# locked with an AAD open authentication policy, and the trigger's callback URL surfaced for an
# action group receiver.
module "logic_app_workflow" {
  source = "../../"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  diagnostics = { log_analytics_workspace_id = module.law.workspace_ids[local.law_name] }

  # The estate default: one shared Sentinel connection every playbook in the call inherits.
  shared_connections = {
    "azuresentinel" = {
      connection_id         = azapi_resource.sentinel_connection.id
      connection_name       = local.conn_name
      managed_api_id        = data.azurerm_managed_api.sentinel.id
      managed_identity_auth = true
    }
  }

  workflows = {
    (local.logic_name) = {
      title = "HTTP - Acknowledge a dispatch and comment on the Sentinel incident"

      definition = templatefile("${path.module}/templates/incident-ack.json.tftpl", {
        comment_prefix = var.comment_prefix
      })

      parameters = {
        comment_suffix = { type = "String", value = "(automated acknowledgement)" }
        # SecureString: the value rides the provider's write-only sensitive_body, so it never
        # appears in the plan output or the state's body attribute.
        notify_webhook_url = { type = "SecureString", value = var.notify_webhook_url }
        # retry_count is deliberately NOT supplied: it has a defaultValue in the definition.
      }

      # The SAS URL an action group receiver would post to.
      callback_trigger_name = "manual"

      # The caller set is not IP-stable (action groups, drills), so the honest IP control is the
      # visible wide allow; the AAD open authentication policy admits token-bearing callers
      # ALONGSIDE the SAS (Consumption keeps SAS valid unless sasAuthenticationPolicy disables
      # it). aud is REQUIRED in every policy (the RP rejects a policy without it, proven live);
      # the ARM audience here means a plain `az account get-access-token` bearer proves the path.
      access_control = {
        trigger = {
          allowed_ips = ["0.0.0.0/0"]
          open_authentication_policies = {
            "same_tenant_caller" = {
              claims = {
                aud = "https://management.core.windows.net/"
                iss = "https://sts.windows.net/${data.azurerm_client_config.current.tenant_id}/"
              }
            }
          }
        }
      }
    }

    # The paste-in path, unedited on purpose: this template is a portal code view export exactly as
    # the designer hands it over, wrapper and all ({"definition": {...}, "parameters": {...}}), with
    # a single ctrl+F token. The module unwraps it and DROPS the wrapper's parameter values, because
    # those belong to the environment it was exported from, so run_note below is the value that
    # actually deploys and reconciliation_window_hours falls back to its defaultValue.
    (local.paste_name) = {
      title = "Recurrence - Reconcile a window and compose a run summary (pasted from the portal code view)"

      definition = templatefile("${path.module}/templates/portal-code-view-export.json.tftpl", {
        summary_prefix = var.comment_prefix
      })

      parameters = {
        run_note = { type = "String", value = "supplied by Terraform, not by the pasted wrapper" }
      }

      # Nothing here rides a managed connector, so it opts out of the shared Sentinel connection
      # the rest of the call inherits (a connection a definition never references is attack
      # surface, and a check would flag it).
      use_shared_connections = false
    }
  }
}
