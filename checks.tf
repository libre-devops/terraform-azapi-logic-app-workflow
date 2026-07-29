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

# $connections declared with nothing wired to it is the one valueless parameter the platform lets
# through: the portal exports the declaration with "defaultValue": {}, so the empty object
# satisfies the deploy and every connector action then fails at RUN time looking up a connection
# that is not there. (Every OTHER valueless parameter fails the deploy outright, so that one is a
# hard validation on var.workflows rather than a warning here.) This is the paste-in trap: a
# definition lifted from the portal declares $connections because the source environment had
# connections, and unwrapping deliberately drops that environment's connection ids.
check "connections_parameter_is_wired" {
  assert {
    condition = alltrue([
      for k, w in var.workflows :
      !contains(keys(try(local.definitions[k].parameters, {})), "$connections") ||
      length(local.effective_connections[k]) > 0
    ])
    error_message = "At least one workflow declares the $connections parameter with no connections configured: it deploys, then every connector action fails at RUN time. Wire the connection through connections or shared_connections, or drop the declaration."
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
