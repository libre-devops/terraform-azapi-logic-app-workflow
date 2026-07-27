output "identities" {
  description = "The workflow identities (principal and tenant ids), for role assignments."
  value       = module.logic_app_workflow.identities
}

output "ids" {
  description = "The workflow resource ids."
  value       = module.logic_app_workflow.ids
}
