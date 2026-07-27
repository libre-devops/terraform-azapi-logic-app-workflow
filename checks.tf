# Post-plan sanity checks: informational (warn), they never fail an apply.

check "has_workflows" {
  assert {
    condition     = length(var.workflows) > 0
    error_message = "No workflows are defined: the module call creates nothing."
  }
}

# A definition with no trigger deploys cleanly, but nothing can ever run it. Usually a template
# token slip rather than a decision, so it should be visible on every plan.
check "definitions_have_triggers" {
  assert {
    condition     = alltrue([for k, d in local.definitions : try(length(keys(d.triggers)) > 0, false)])
    error_message = "At least one workflow definition declares NO trigger: the workflow deploys but can never run."
  }
}

# A connection the definition never references is usually a leftover from a lift, and every
# $connections entry is attack surface an auditor has to explain. Substring match on the raw
# definition text: managed connector bodies always name the api key inside
# @parameters('$connections')['<api name>'].
check "connections_are_referenced" {
  assert {
    condition = alltrue(flatten([
      for k, w in var.workflows : [
        for api_name in keys(local.effective_connections[k]) : strcontains(w.definition, api_name)
      ]
    ]))
    error_message = "At least one workflow carries a connection its definition never references: drop the connection, or set use_shared_connections = false on workflows that do not use the shared set."
  }
}

# A declared parameter with neither a supplied value nor a defaultValue deploys cleanly and then
# fails at RUN time, the worst place to find out. ($connections is exempt: its value is generated
# from the connections maps.)
check "declared_parameters_have_values" {
  assert {
    condition = alltrue(flatten([
      for k, w in var.workflows : [
        for p_name, p_def in try(local.definitions[k].parameters, {}) :
        p_name == "$connections" || contains(keys(w.parameters), p_name) || contains(try(keys(p_def), []), "defaultValue")
      ]
    ]))
    error_message = "At least one definition parameter has neither a supplied value nor a defaultValue: the workflow deploys but the run fails when the parameter is read."
  }
}

# SAS off with no open authentication policy means NOTHING can call the trigger over plain HTTP:
# legitimate for workflows invoked only by native Workflow dispatch or connector triggers, but it
# should never be a surprise.
check "sas_off_without_policies_is_visible" {
  assert {
    condition = alltrue([
      for w in values(var.workflows) :
      try(w.access_control.trigger.sas_authentication_enabled, true) ||
      length(try(w.access_control.trigger.open_authentication_policies, {})) > 0
    ])
    error_message = "At least one workflow disables SAS with NO open authentication policy: its trigger accepts no HTTP caller at all (only native Workflow dispatch and connector triggers can start it)."
  }
}
