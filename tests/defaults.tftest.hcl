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

# The portal code view wraps the definition under a top-level "definition" key and carries the
# SOURCE environment's parameter VALUES beside it. Paste it straight in: the definition unwraps and
# deploys, and the wrapper's values are dropped, because values come from the parameters input.
run "code_view_envelope_unwraps" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Pasted straight from the portal code view"
        definition = <<-DEF
          {
            "definition": {
              "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
              "contentVersion": "1.0.0.0",
              "parameters": {
                "greeting": { "type": "String", "defaultValue": "hello" }
              },
              "triggers": {
                "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
              },
              "actions": {
                "Compose_greeting": { "type": "Compose", "inputs": "@parameters('greeting')", "runAfter": {} }
              },
              "outputs": {}
            },
            "parameters": {
              "greeting": { "value": "hello from the source environment" }
            }
          }
        DEF
      }
    }
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.definition.triggers.Recurrence_daily.type == "Recurrence"
    error_message = "The code view envelope should unwrap: properties.definition must be the INNER definition."
  }

  assert {
    condition     = !contains(keys(azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.definition), "definition")
    error_message = "The wrapper must never be deployed inside itself."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters.greeting.value == "hello from the source environment"
    error_message = "The wrapper's parameter VALUES must be ADOPTED: a portal export carries every value its definition declares, so a paste has to deploy untouched."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.definition.parameters.greeting.defaultValue == "hello"
    error_message = "Adopting a wrapper value must not rewrite the definition's own defaultValue; the value simply outranks it."
  }
}

# The other thing you can paste: an ARM resource GET (az rest, az logic workflow show), which wraps
# the definition one level deeper under properties, beside the source resource's own state.
run "arm_resource_shape_unwraps" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Pasted from an ARM resource GET"
        definition = <<-DEF
          {
            "id": "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-source/providers/Microsoft.Logic/workflows/logic-source-01",
            "name": "logic-source-01",
            "type": "Microsoft.Logic/workflows",
            "location": "westeurope",
            "properties": {
              "state": "Disabled",
              "definition": {
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
              },
              "parameters": {}
            }
          }
        DEF
      }
    }
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.definition.triggers.Recurrence_daily.type == "Recurrence"
    error_message = "The ARM resource shape should unwrap from properties.definition."
  }

  assert {
    condition     = !contains(keys(azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.definition), "properties")
    error_message = "The ARM wrapper must never be deployed inside the definition."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.state == "Enabled"
    error_message = "The SOURCE resource's state must not ride along: state comes from the enabled input."
  }
}

# The sharp edge of paste-in: the envelope's $connections VALUE names the source environment's
# connection. It must be dropped and regenerated from the connections input, or a paste silently
# deploys a workflow pointing at another environment's connection.
run "code_view_envelope_connections_are_regenerated" {
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
        title      = "Recurrence - Pasted with the source environment's connection"
        definition = <<-DEF
          {
            "definition": {
              "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
              "contentVersion": "1.0.0.0",
              "parameters": {
                "$connections": { "type": "Object", "defaultValue": {} }
              },
              "triggers": {
                "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
              },
              "actions": {
                "Get_incident": {
                  "type": "ApiConnection",
                  "runAfter": {},
                  "inputs": {
                    "host": { "connection": { "name": "@parameters('$connections')['azuresentinel']['connectionId']" } },
                    "method": "get",
                    "path": "/Incidents"
                  }
                }
              },
              "outputs": {}
            },
            "parameters": {
              "$connections": {
                "value": {
                  "azuresentinel": {
                    "connectionId": "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-source/providers/Microsoft.Web/connections/conn-from-another-estate",
                    "connectionName": "conn-from-another-estate",
                    "id": "/subscriptions/99999999-9999-9999-9999-999999999999/providers/Microsoft.Web/locations/westeurope/managedApis/azuresentinel"
                  }
                }
              }
            }
          }
        DEF
      }
    }
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters["$connections"].value.azuresentinel.connectionId == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Web/connections/conn-sentinel"
    error_message = "The generated $connections value must replace the pasted one: the source environment's connection id must never survive the paste."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters["$connections"].value.azuresentinel.connectionProperties.authentication.type == "ManagedServiceIdentity"
    error_message = "Managed identity auth should still be generated for a pasted definition."
  }
}

# Validation: a wrapper carrying a fragment is still a fragment.
run "rejects_wrapper_with_incomplete_definition" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Wrapped fragment"
        definition = "{\"definition\": {\"$schema\": \"x\", \"contentVersion\": \"1.0.0.0\"}}"
      }
    }
  }

  expect_failures = [var.workflows]
}

# Validation: the wrapper's parameters block holds VALUES, not DECLARATIONS. A value supplied for a
# parameter that only ever appears out there is still undeclared, and still rejected.
run "rejects_value_for_wrapper_only_parameter" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Wrapper-only parameter"
        definition = <<-DEF
          {
            "definition": {
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
            },
            "parameters": {
              "greeting": { "value": "hello from the source environment" }
            }
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

# Validation: a declared parameter with neither a value nor a defaultValue is rejected at plan,
# because the engine rejects it at DEPLOY (InvalidTemplate, "the value ... is not provided",
# proven against the ARM validate endpoint).
run "rejects_valueless_parameter" {
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

  expect_failures = [var.workflows]
}

# $connections is the exception the platform lets through: the portal exports it with
# "defaultValue": {}, so an unwired declaration deploys and then fails at RUN time. A check, not a
# validation, because it is a real (if unusual) intermediate state.
run "warns_on_declared_connections_without_wiring" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Pasted connector workflow with no connection wired"
        definition = <<-DEF
          {
            "definition": {
              "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
              "contentVersion": "1.0.0.0",
              "parameters": {
                "$connections": { "type": "Object", "defaultValue": {} }
              },
              "triggers": {
                "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
              },
              "actions": {
                "Get_incident": {
                  "type": "ApiConnection",
                  "runAfter": {},
                  "inputs": {
                    "host": { "connection": { "name": "@parameters('$connections')['azuresentinel']['connectionId']" } },
                    "method": "get",
                    "path": "/Incidents"
                  }
                }
              },
              "outputs": {}
            },
            "parameters": {
              "$connections": {
                "value": {
                  "azuresentinel": { "connectionId": "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-source/providers/Microsoft.Web/connections/conn-from-another-estate" }
                }
              }
            }
          }
        DEF
      }
    }
  }

  expect_failures = [check.connections_parameter_is_wired]
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

  assert {
    condition     = length(azapi_resource.last) == 0
    error_message = "Tier 2 should be empty when nothing dispatches to a dispatcher."
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
        deploy_tier = 3
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

# Validation: an open authentication policy without an aud claim is rejected at plan (the
# platform requires aud: MissingOAuthRequiredClaimValue, proven live).
run "rejects_policy_without_aud" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "HTTP - Policy missing aud"
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
          trigger = {
            allowed_ips = ["0.0.0.0/0"]
            open_authentication_policies = {
              "issonly" = {
                claims = {
                  iss = "https://sts.windows.net/00000000-0000-0000-0000-000000000000/"
                }
              }
            }
          }
        }
      }
    }
  }

  expect_failures = [var.workflows]
}

# sas_authentication_enabled = false emits the Disabled policy; the default emits nothing (the
# platform default, SAS on, stays implicit).
run "sas_off_renders_policy" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "HTTP - AAD-only trigger"
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
          trigger = {
            allowed_ips                = ["0.0.0.0/0"]
            sas_authentication_enabled = false
            open_authentication_policies = {
              "caller" = {
                claims = {
                  aud = "https://management.core.windows.net/"
                  iss = "https://sts.windows.net/00000000-0000-0000-0000-000000000000/"
                }
              }
            }
          }
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.accessControl.triggers.sasAuthenticationPolicy.state == "Disabled"
    error_message = "sas_authentication_enabled = false should emit the Disabled SAS policy."
  }
}

run "sas_default_is_implicit" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "HTTP - Default SAS trigger"
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
          trigger = { allowed_ips = ["0.0.0.0/0"] }
        }
      }
    }
  }

  assert {
    condition     = !contains(keys(azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.accessControl.triggers), "sasAuthenticationPolicy")
    error_message = "The default (SAS on) should emit NO sasAuthenticationPolicy: omission is the platform default."
  }
}

# SAS off with no policy leaves the trigger with no HTTP door at all; the check makes it visible.
run "warns_on_sas_off_without_policies" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "HTTP - Dispatch-only trigger"
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
          trigger = {
            allowed_ips                = ["0.0.0.0/0"]
            sas_authentication_enabled = false
          }
        }
      }
    }
  }

  expect_failures = [check.sas_off_without_policies_is_visible]
}

# ---------------------------------------------------------------------------------------------
# Wrapper value adoption (4.4.0). A pasted wrapper carries every value its definition declares,
# so it must deploy untouched. These pin the boundaries of that.
# ---------------------------------------------------------------------------------------------

# The whole point: a code view export with NO parameters input and NO defaultValue anywhere still
# plans, because the wrapper supplied the value. This is the case that used to fail.
run "wrapper_values_satisfy_declarations_with_no_input" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Pasted with values, nothing supplied"
        definition = <<-DEF
          {
            "definition": {
              "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
              "contentVersion": "1.0.0.0",
              "parameters": {
                "tenant_id": { "type": "String" },
                "retry_count": { "type": "Int" },
                "category_map": { "type": "Array" }
              },
              "triggers": {
                "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
              },
              "actions": {
                "Compose_tenant": { "type": "Compose", "inputs": "@parameters('tenant_id')", "runAfter": {} }
              },
              "outputs": {}
            },
            "parameters": {
              "tenant_id": { "value": "11111111-2222-3333-4444-555555555555" },
              "retry_count": { "value": 3 },
              "category_map": { "value": [{ "contains": "x", "value": "y" }] }
            }
          }
        DEF
      }
    }
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters.tenant_id.value == "11111111-2222-3333-4444-555555555555"
    error_message = "A wrapper's String value must be adopted verbatim."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters.retry_count.value == 3
    error_message = "A wrapper's value keeps its real JSON type; it is not restringified."
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters.category_map.value[0].contains == "x"
    error_message = "A wrapper's Array value must survive adoption intact."
  }
}

# The explicit input still wins, so adoption can never quietly override what you configured.
run "explicit_parameters_outrank_wrapper_values" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title = "Recurrence - Explicit beats pasted"
        parameters = {
          greeting = { type = "String", value = "from terraform" }
        }
        definition = <<-DEF
          {
            "definition": {
              "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
              "contentVersion": "1.0.0.0",
              "parameters": { "greeting": { "type": "String" } },
              "triggers": {
                "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
              },
              "actions": {
                "Compose_greeting": { "type": "Compose", "inputs": "@parameters('greeting')", "runAfter": {} }
              },
              "outputs": {}
            },
            "parameters": { "greeting": { "value": "from the source environment" } }
          }
        DEF
      }
    }
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters.greeting.value == "from terraform"
    error_message = "The parameters input must outrank a value the wrapper carried."
  }
}

# The trap this change could have walked into: a BARE definition's top-level "parameters" is its
# DECLARATIONS, not values. Reading those as values would make the validation vacuous and deploy a
# declaration object as a value, so a bare definition must contribute nothing.
run "bare_definition_declarations_are_not_values" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Bare definition, declarations only"
        definition = <<-DEF
          {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": { "greeting": { "type": "String" } },
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

  expect_failures = [var.workflows]
}

# Secrets stay out of the definition: a SecureString declaration carrying only a wrapper value is
# still rejected, so the secret has to arrive through the input and ride sensitive_body.
run "rejects_secure_parameter_supplied_only_by_wrapper" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title      = "Recurrence - Secret pasted in the wrapper"
        definition = <<-DEF
          {
            "definition": {
              "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
              "contentVersion": "1.0.0.0",
              "parameters": { "api_key": { "type": "SecureString" } },
              "triggers": {
                "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
              },
              "actions": {
                "Compose_key": { "type": "Compose", "inputs": "@parameters('api_key')", "runAfter": {} }
              },
              "outputs": {}
            },
            "parameters": { "api_key": { "value": "s3cret-typed-into-the-designer" } }
          }
        DEF
      }
    }
  }

  expect_failures = [var.workflows]
}

# A wrapper's $connections is the source environment's resolved block; the module regenerates it
# from the connections input and must never adopt the pasted one.
run "wrapper_connections_value_is_not_adopted" {
  command = plan

  variables {
    workflows = {
      "logic-ldo-uks-tst-01" = {
        title = "Recurrence - Pasted $connections ignored"
        connections = {
          "someapi" = {
            connection_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Web/connections/conn-someapi"
            managed_api_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Web/locations/uksouth/managedApis/someapi"
          }
        }
        definition = <<-DEF
          {
            "definition": {
              "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
              "contentVersion": "1.0.0.0",
              "parameters": { "$connections": { "type": "Object", "defaultValue": {} } },
              "triggers": {
                "Recurrence_daily": { "type": "Recurrence", "recurrence": { "frequency": "Day", "interval": 1 } }
              },
              "actions": {
                "Compose_noop": { "type": "Compose", "inputs": "noop", "runAfter": {} }
              },
              "outputs": {}
            },
            "parameters": {
              "$connections": { "value": { "someapi": { "connectionId": "/subscriptions/SOURCE/x", "connectionName": "someapi", "id": "/subscriptions/SOURCE/y" } } }
            }
          }
        DEF
      }
    }
  }

  assert {
    condition     = azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters["$connections"].value.someapi.connectionId == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Web/connections/conn-someapi"
    error_message = "$connections must be GENERATED from the connections input, never adopted from the paste."
  }

  assert {
    condition     = !strcontains(jsonencode(azapi_resource.this["logic-ldo-uks-tst-01"].body.properties.parameters["$connections"]), "/subscriptions/SOURCE/")
    error_message = "A pasted $connections names the SOURCE environment's connection resources and must not survive anywhere in the deployed value."
  }
}
