locals {
  location   = lookup(var.regions, var.loc, "uksouth")
  rg_name    = "rg-${var.short}-${var.loc}-${terraform.workspace}-001"
  logic_name = "logic-${var.short}-${var.loc}-${terraform.workspace}-01"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

# One workflow, deployed WHOLE: the definition is the portal code-view export, held verbatim in
# templates/ with one scalar token substituted by templatefile. Free at rest; the daily run costs
# fractions of a penny.
module "logic_app_workflow" {
  source = "../../"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  workflows = {
    (local.logic_name) = {
      title = "Recurrence - Compose a daily greeting"

      definition = templatefile("${path.module}/templates/daily-greeting.json.tftpl", {
        greeting = "hello from ${local.logic_name}"
      })
    }
  }
}
