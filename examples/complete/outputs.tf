output "access_endpoints" {
  description = "The workflow access endpoints."
  value       = module.logic_app_workflow.access_endpoints
}

output "callback_urls" {
  description = "The manual trigger's invoke URL, for an action group receiver. Sensitive: the SAS grants invoke."
  value       = module.logic_app_workflow.callback_urls
  sensitive   = true
}

output "diagnostic_setting_ids" {
  description = "The diagnostic setting ids."
  value       = module.logic_app_workflow.diagnostic_setting_ids
}

output "identities" {
  description = "The workflow identities (principal and tenant ids), for role assignments."
  value       = module.logic_app_workflow.identities
}

output "ids" {
  description = "The workflow resource ids."
  value       = module.logic_app_workflow.ids
}
