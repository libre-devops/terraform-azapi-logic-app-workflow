# Plan-time tests for the module. The provider is mocked, so no credentials and no cloud calls:
#   terraform init -backend=false && terraform test

mock_provider "azapi" {}

variables {
  location          = "uksouth"
  resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01"

  workflows = {
    "logic-ldo-uks-tst-01" = {
      title      = "Recurrence - Compose a daily greeting"
      definition = <<-DEF
        {
          "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
          "contentVersion": "1.0.0.0",
          "parameters": {},
          "triggers": {
            "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
          },
          "actions": {
            "Compose_greeting": { "type": "Compose", "inputs": "hello", "runAfter": {} }
          },
          "outputs": {}
        }
      DEF
    }
  }
}

# Defaults render: the map key is the resource name, the versioned type lands, the definition
# deploys VERBATIM (decoded, never reshaped), no parameters block is sent when there is nothing
# to send, the title becomes the hidden-title tag, and the identity is SystemAssigned.
run "defaults_render" {
  command = plan

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].name == "logic-ldo-uks-tst-01"
    error_message = "The map key should be the resource name."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].type == "Microsoft.Logic/workflows@2019-05-01"
    error_message = "The default api_version should land in the resource type."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.state == "Enabled"
    error_message = "enabled should default to true (state Enabled)."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.definition.triggers.Recurrence_daily.type == "Recurrence"
    error_message = "The definition should deploy verbatim (jsondecode, no reshaping)."
  }

  assert {
    condition     = !contains(keys(azapi_resource.this["logic-ldo-uks-tst-01"].body.properties), "parameters")
    error_message = "With no parameter values and no connections, the parameters block should be OMITTED, never sent empty."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].tags["hidden-title"] == "Recurrence - Compose a daily greeting"
    error_message = "The title should land as the hidden-title tag."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].identity[0].type == "SystemAssigned"
    error_message = "The identity should default to SystemAssigned."
  }

  assert {
    condition     = length(azapi_resource.diagnostics) == 0
    error_message = "No diagnostics input should mean no diagnostic settings."
  }
}

# Typed parameter values convert from the string input convention to real JSON types.
run "parameters_convert" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Compose a parameterised greeting"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {
              "greeting": { "type": "String" },
              "retry_count": { "type": "Int" },
              "verbose": { "type": "Bool" },
              "settings": { "type": "Object" }
            },
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "@parameters('greeting')", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF

        parameters = {
          greeting    = { type = "String", value = "hello" }
          retry_count = { type = "Int", value = "3" }
          verbose     = { type = "Bool", value = "true" }
          settings    = { type = "Object", value = "{\"mode\": \"strict\"}" }
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters.greeting.value == "hello"
    error_message = "String values should pass through."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters.retry_count.value == 3
    error_message = "Int values should convert to real numbers."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters.verbose.value == true
    error_message = "Bool values should convert to real booleans."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters.settings.value.mode == "strict"
    error_message = "Object values should jsondecode to real objects."
  }
}

# Secure parameter values ride sensitive_body: they must never appear in the body attribute
# (the write-only sensitive_body itself is not observable in a plan, which is the point).
run "secure_parameters_stay_out_of_body" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Notify a webhook"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {
              "greeting": { "type": "String" },
              "webhook_url": { "type": "SecureString" }
            },
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "HTTP_notify": { "type": "Http", "inputs": { "method": "POST", "uri": "@parameters('webhook_url')", "body": "@parameters('greeting')", "retryPolicy": { "type": "none" } }, "runAfter": {} }
            },
            "outputs": {}
          }
        DEF

        parameters = {
          greeting    = { type = "String", value = "hello" }
          webhook_url = { type = "SecureString", value = "https://hooks.example.com/x" }
        }
      }
    }
  }

  assert {
    condition     = contains(keys(azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters), "greeting")
    error_message = "Non-secure values should stay in the body."
  }

  assert {
    condition     = !contains(keys(azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters), "webhook_url")
    error_message = "Secure values must NOT appear in the body: they ride sensitive_body."
  }
}

# The shared connections generate the whole $connections parameter value, with the managed
# identity authentication block Consumption needs (V1 connection + Alternative auth).
run "connections_generate" {
  command = plan

  variables {
    shared_connections = {
      "azuresentinel" = {
        connection_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Web/connections/conn-sentinel"
        managed_api_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel"
        managed_identity_auth = true
      }
    }

    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "HTTP - Comment on the incident"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {
              "$connections": { "type": "Object", "defaultValue": {} }
            },
            "triggers": {
              "manual": { "type": "Request", "kind": "Http", "inputs": { "schema": {} } }
            },
            "actions": {
              "Add_comment": { "type": "ApiConnection", "inputs": { "host": { "connection": { "name": "@parameters('$connections')['azuresentinel']['connectionId']" } }, "method": "post", "path": "/Incidents/Comment" }, "runAfter": {} }
            },
            "outputs": {}
          }
        DEF
      }
    }
  }

  assert {
    condition     = endswith(azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters["$connections"].value.azuresentinel.connectionId, "connections/conn-sentinel")
    error_message = "The shared connection id should land in the $connections value."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters["$connections"].value.azuresentinel.connectionName == "azuresentinel"
    error_message = "connection_name should default to the managed API key."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters["$connections"].value.azuresentinel.connectionProperties.authentication.type == "ManagedServiceIdentity"
    error_message = "managed_identity_auth should generate the ManagedServiceIdentity authentication block."
  }
}

# A user assigned workflow: its own connections win over shared by key, and the authentication
# block names the user assigned identity (a bare block would mean SystemAssigned, which the
# platform rejects when no system identity exists).
run "user_assigned_connections_name_the_identity" {
  command = plan

  variables {
    shared_connections = {
      "azuresentinel" = {
        connection_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Web/connections/conn-shared"
        managed_api_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel"
        managed_identity_auth = true
      }
    }

    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "HTTP - Comment on the incident as the shared automation identity"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {
              "$connections": { "type": "Object", "defaultValue": {} }
            },
            "triggers": {
              "manual": { "type": "Request", "kind": "Http", "inputs": { "schema": {} } }
            },
            "actions": {
              "Add_comment": { "type": "ApiConnection", "inputs": { "host": { "connection": { "name": "@parameters('$connections')['azuresentinel']['connectionId']" } }, "method": "post", "path": "/Incidents/Comment" }, "runAfter": {} }
            },
            "outputs": {}
          }
        DEF

        identity = {
          type         = "UserAssigned"
          identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai-soc"]
        }
        connections_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai-soc"

        connections = {
          "azuresentinel" = {
            connection_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Web/connections/conn-own"
            managed_api_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel"
            managed_identity_auth = true
          }
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].identity[0].type == "UserAssigned"
    error_message = "The identity type should flow through."
  }

  assert {
    condition     = endswith(azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters["$connections"].value.azuresentinel.connectionId, "connections/conn-own")
    error_message = "A workflow's own connection should win over the shared one by key."
  }

  assert {
    condition     = endswith(azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters["$connections"].value.azuresentinel.connectionProperties.authentication.identity, "userAssignedIdentities/uai-soc")
    error_message = "connections_identity_id should be named inside the authentication block."
  }
}

# Access control maps to properties.accessControl: IP ranges become addressRange objects and
# open authentication policies become AAD claim lists. Unset sections are omitted.
run "access_control_maps" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "HTTP - Locked-down trigger"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
              "manual": { "type": "Request", "kind": "Http", "inputs": { "schema": {} } }
            },
            "actions": {
              "Compose_ack": { "type": "Compose", "inputs": "ok", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF

        access_control = {
          action_allowed_ips = ["10.1.0.0/24"]
          trigger = {
            allowed_ips = ["10.0.0.0/24"]
            open_authentication_policies = {
              "actiongroup" = {
                claims = {
                  iss = "https://sts.windows.net/00000000-0000-0000-0000-000000000000/"
                  aud = "https://management.core.windows.net/"
                }
              }
            }
          }
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.accessControl.triggers.allowedCallerIpAddresses[0].addressRange == "10.0.0.0/24"
    error_message = "Trigger IP ranges should map to addressRange objects."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.accessControl.triggers.openAuthenticationPolicies.policies.actiongroup.type == "AAD"
    error_message = "Open authentication policies should be typed AAD."
  }

  assert {
    condition = anytrue([
      for c in azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.accessControl.triggers.openAuthenticationPolicies.policies.actiongroup.claims :
      c.name == "iss" && endswith(c.value, "0000/")
    ])
    error_message = "Policy claims should become name/value objects."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.accessControl.actions.allowedCallerIpAddresses[0].addressRange == "10.1.0.0/24"
    error_message = "Action IP ranges should map to addressRange objects."
  }

  assert {
    condition     = !contains(keys(azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.accessControl), "contents")
    error_message = "Unset access control sections should be omitted."
  }
}

# enabled = false lands as state Disabled, and module/per-workflow tags merge with the
# hidden-title always winning.
run "disabled_state_and_tags_merge" {
  command = plan

  variables {
    tags = { Environment = "tst", CostCentre = "1888" }

    workflows = {
      "logic-ldo-uks-tst-01" = {
        title   = "Recurrence - Parked workflow"
        enabled = false
        tags    = { CostCentre = "override", "hidden-title" = "never-wins" }

        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "hello", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF
      }
    }
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.state == "Disabled"
    error_message = "enabled = false should land as state Disabled."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].tags["CostCentre"] == "override"
    error_message = "Per-workflow tags should win over module tags by key."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].tags["Environment"] == "tst"
    error_message = "Module tags should still land."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].tags["hidden-title"] == "Recurrence - Parked workflow"
    error_message = "The hidden-title tag always carries the title, even against an explicit tag."
  }
}

# Diagnostics: the module-level default reaches every workflow, a per-workflow name override
# wins, and diagnostics_enabled = false opts out.
run "diagnostics_render" {
  command = plan

  variables {
    diagnostics = { log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.OperationalInsights/workspaces/log-ldo-uks-tst-01" }

    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Default diagnostics"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "hello", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF
      }

      "logic-ldo-uks-tst-02" = {
        title      = "Recurrence - Named diagnostics"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "hello", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF

        diagnostics = {
          log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.OperationalInsights/workspaces/log-ldo-uks-tst-02"
          name                       = "diag-custom"
        }
      }

      "logic-ldo-uks-tst-03" = {
        title               = "Recurrence - No diagnostics"
        diagnostics_enabled = false
        definition          = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "hello", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF
      }
    }
  }

  assert {
    condition     = azapi_resource.diagnostics["logic-ldo-uks-tst-01"].name == "diag-logic-ldo-uks-tst-01"
    error_message = "The default diagnostic setting should be named diag-<workflow>."
  }

  assert {
    condition     = azapi_resource.diagnostics["logic-ldo-uks-tst-01"].body.properties.logs[0].categoryGroup == "allLogs"
    error_message = "The diagnostic setting should send allLogs."
  }

  assert {
    condition     = azapi_resource.diagnostics["logic-ldo-uks-tst-02"].name == "diag-custom"
    error_message = "A per-workflow diagnostics name should win."
  }

  assert {
    condition     = length(azapi_resource.diagnostics) == 2
    error_message = "diagnostics_enabled = false should opt the workflow out."
  }
}

# callback_trigger_name lists the named trigger's callback URL through the action data source.
run "callback_url_listed" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title                 = "HTTP - Invoked by an action group"
        callback_trigger_name = "manual"
        definition            = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
              "manual": { "type": "Request", "kind": "Http", "inputs": { "schema": {} } }
            },
            "actions": {
              "Compose_ack": { "type": "Compose", "inputs": "ok", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF
      }
    }
  }

  assert {
    condition     = data.azapi_resource_action.callback_url["logic-ldo-uks-tst-01"].action == "listCallbackUrl"
    error_message = "The callback URL should come from listCallbackUrl."
  }

  assert {
    condition     = data.azapi_resource_action.callback_url["logic-ldo-uks-tst-01"].method == "POST"
    error_message = "listCallbackUrl is a POST action."
  }
}

# Validation: a definition that is not valid JSON is rejected.
run "rejects_invalid_json_definition" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Broken"
        definition = "not json"
      }
    }
  }

  expect_failures = [var.workflows]
}

# Validation: a fragment (valid JSON, but not a complete definition) is rejected.
run "rejects_incomplete_definition" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Fragment"
        definition = "{\"$schema\": \"x\", \"contentVersion\": \"1.0.0.0\"}"
      }
    }
  }

  expect_failures = [var.workflows]
}

# Validation: a parameter value for a parameter the definition never declares is rejected.
run "rejects_undeclared_parameter_value" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Undeclared parameter"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "hello", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF

        parameters = {
          greeting = { type = "String", value = "hello" }
        }
      }
    }
  }

  expect_failures = [var.workflows]
}

# Validation: supplying $connections yourself is rejected (the connections map generates it).
run "rejects_supplied_connections_parameter" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Hand-rolled connections"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {
              "$connections": { "type": "Object", "defaultValue": {} }
            },
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "hello", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF

        parameters = {
          "$connections" = { type = "Object", value = "{}" }
        }
      }
    }
  }

  expect_failures = [var.workflows]
}

# Validation: connections on a definition that never declares $connections are rejected (the PUT
# would be too, but at plan time and with a message that says why).
run "rejects_connections_without_declaration" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Missing $connections declaration"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_azuresentinel": { "type": "Compose", "inputs": "azuresentinel", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF

        connections = {
          "azuresentinel" = {
            connection_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Web/connections/conn-sentinel"
            managed_api_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel"
          }
        }
      }
    }
  }

  expect_failures = [var.workflows]
}

# Validation: an unknown identity type is rejected.
run "rejects_bad_identity_type" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Bad identity"
        identity   = { type = "Nope" }
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "hello", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF
      }
    }
  }

  expect_failures = [var.workflows]
}

# Validation: UserAssigned without any identity id is rejected.
run "rejects_user_assigned_without_ids" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - UAI without ids"
        identity   = { type = "UserAssigned" }
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "hello", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF
      }
    }
  }

  expect_failures = [var.workflows]
}

# Validation: a UserAssigned workflow with managed identity authenticated connections but no
# connections_identity_id is rejected (the platform would reject the bare authentication block).
run "rejects_user_assigned_msi_connection_without_identity_id" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title = "HTTP - UAI connection without identity id"
        identity = {
          type         = "UserAssigned"
          identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uai-soc"]
        }
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {
              "$connections": { "type": "Object", "defaultValue": {} }
            },
            "triggers": {
              "manual": { "type": "Request", "kind": "Http", "inputs": { "schema": {} } }
            },
            "actions": {
              "Add_comment": { "type": "ApiConnection", "inputs": { "host": { "connection": { "name": "@parameters('$connections')['azuresentinel']['connectionId']" } }, "method": "post", "path": "/Incidents/Comment" }, "runAfter": {} }
            },
            "outputs": {}
          }
        DEF

        connections = {
          "azuresentinel" = {
            connection_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Web/connections/conn-sentinel"
            managed_api_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel"
            managed_identity_auth = true
          }
        }
      }
    }
  }

  expect_failures = [var.workflows]
}

# Validation: callback_trigger_name must name a trigger the definition declares.
run "rejects_bad_callback_trigger" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title                 = "Recurrence - Bad callback trigger"
        callback_trigger_name = "manual"
        definition            = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "hello", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF
      }
    }
  }

  expect_failures = [var.workflows]
}

# Validation: an unknown parameter type is rejected.
run "rejects_bad_parameter_type" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Bad parameter type"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {
              "greeting": { "type": "String" }
            },
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "@parameters('greeting')", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF

        parameters = {
          greeting = { type = "Text", value = "hello" }
        }
      }
    }
  }

  expect_failures = [var.workflows]
}

# Validation: a value that cannot convert to its declared type is rejected.
run "rejects_unconvertible_parameter_value" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Unconvertible value"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {
              "retry_count": { "type": "Int" }
            },
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "@parameters('retry_count')", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF

        parameters = {
          retry_count = { type = "Int", value = "abc" }
        }
      }
    }
  }

  expect_failures = [var.workflows]
}

# An empty map creates nothing and says so.
run "warns_on_empty" {
  command = plan

  variables {
    workflows = {}
  }

  expect_failures = [check.has_workflows]
}

# A definition with no trigger deploys but can never run; the check makes it visible.
run "warns_on_no_triggers" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Draft - No trigger yet"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {},
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "hello", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF
      }
    }
  }

  expect_failures = [check.definitions_have_triggers]
}

# A connection the definition never references trips the leftover-connection check.
run "warns_on_unreferenced_connection" {
  command = plan

  variables {
    shared_connections = {
      "servicenow" = {
        connection_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Web/connections/conn-snow"
        managed_api_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Web/locations/uksouth/managedApis/service-now"
      }
    }

    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Unused connection"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {
              "$connections": { "type": "Object", "defaultValue": {} }
            },
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "hello", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF
      }
    }
  }

  expect_failures = [check.connections_are_referenced]
}

# A declared parameter with neither a value nor a defaultValue trips the run-time-failure check.
run "warns_on_valueless_parameter" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Valueless parameter"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {
              "greeting": { "type": "String" }
            },
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "@parameters('greeting')", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF
      }
    }
  }

  expect_failures = [check.declared_parameters_have_values]
}

# Tier-1 workflows deploy through the late resource, after every tier-0 workflow (ARM validates a
# native Workflow dispatch action's target at PUT time: NestedWorkflowNotFound, proven live).
run "tier_one_deploys_late" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Leaf workflow"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "hello", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF
      }

      "logic-ldo-uks-tst-02" = {
        title       = "HTTP - Dispatches to the leaf by constructed id"
        deploy_tier = 1
        definition  = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
              "manual": { "type": "Request", "kind": "Http", "inputs": { "schema": {} } }
            },
            "actions": {
              "Dispatch_leaf": { "type": "Workflow", "inputs": { "host": { "triggerName": "Recurrence_daily", "workflow": { "id": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Logic/workflows/logic-ldo-uks-tst-01" } } }, "runAfter": {} }
            },
            "outputs": {}
          }
        DEF
      }
    }
  }

  assert {
    condition     = contains(keys(azapi_resource.this), "logic-ldo-uks-tst-01") && !contains(keys(azapi_resource.this), "logic-ldo-uks-tst-02")
    error_message = "Tier 0 should hold only the leaf workflow."
  }

  assert {
    condition     = contains(keys(azapi_resource.late), "logic-ldo-uks-tst-02") && length(azapi_resource.late) == 1
    error_message = "Tier 1 should hold only the dispatching workflow."
  }
}

# The default response_export_values is the trimmed stable set, never ["*"]: the full GET echo
# includes volatile fields (changedTime and friends) that make every plan a no-op update.
run "default_exports_are_trimmed" {
  command = plan

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].response_export_values == tolist(["identity", "properties.accessEndpoint", "properties.state", "properties.endpointsConfiguration"])
    error_message = "The default response_export_values should be the trimmed stable set."
  }
}

# Validation: only tiers 0 and 1 exist.
run "rejects_bad_tier" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title       = "Recurrence - Bad tier"
        deploy_tier = 2
        definition  = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
              "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
            },
            "actions": {
              "Compose_greeting": { "type": "Compose", "inputs": "hello", "runAfter": {} }
            },
            "outputs": {}
          }
        DEF
      }
    }
  }

  expect_failures = [var.workflows]
}
