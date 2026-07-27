output "access_endpoints" {
  description = "Map of workflow name to its access endpoint (from the PUT response)."
  value       = { for k, r in azapi_resource.this : k => try(r.output.properties.accessEndpoint, null) }
}

output "callback_urls" {
  description = "Map of workflow name to its callback_trigger_name trigger's invoke URL (the SAS URL an action group receiver or external caller posts to). Sensitive: the SAS grants invoke."
  value       = { for k, d in data.azapi_resource_action.callback_url : k => try(d.output.value, null) }
  sensitive   = true
}

output "diagnostic_setting_ids" {
  description = "Map of workflow name to its diagnostic setting resource id (only workflows with diagnostics)."
  value       = { for k, r in azapi_resource.diagnostics : k => r.id }
}

output "identities" {
  description = "Map of workflow name to its identity { principal_id, tenant_id } (principal_id is populated for system-assigned identities), for role assignments."
  value = {
    for k, r in azapi_resource.this : k => try({
      principal_id = r.identity[0].principal_id
      tenant_id    = r.identity[0].tenant_id
    }, null)
  }
}

output "ids" {
  description = "Map of workflow name to its resource id."
  value       = { for k, r in azapi_resource.this : k => r.id }
}

output "ids_zipmap" {
  description = "Map of workflow name to a { name, id } object, for passing where both are needed together."
  value       = { for k, r in azapi_resource.this : k => { name = r.name, id = r.id } }
}

output "names" {
  description = "The workflow names."
  value       = keys(azapi_resource.this)
}

output "tags" {
  description = "The base tags applied to the workflows."
  value       = var.tags
}

output "workflows" {
  description = "Map of workflow name to { id, name, location, state, and the raw exported properties } for anything the typed outputs do not surface (outbound IPs, endpoints configuration)."
  value = {
    for k, r in azapi_resource.this : k => {
      id         = r.id
      name       = r.name
      location   = r.location
      state      = try(r.output.properties.state, null)
      properties = try(r.output.properties, null)
    }
  }
}
