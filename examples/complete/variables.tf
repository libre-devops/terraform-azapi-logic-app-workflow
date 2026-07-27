variable "comment_prefix" {
  description = "Prefix for the acknowledgement comment, substituted into the workflow template by templatefile (the ctrl+F contract)."
  type        = string
  default     = "SOC automation"
}

# Forwarded into the tags module for the DeployedBranch / DeployedRepo tags. The terraform-azure
# action fills these in CI via TF_VAR_deployed_branch / TF_VAR_deployed_repo; empty when run locally.
variable "deployed_branch" {
  description = "Git branch the deployment came from. Auto-filled in CI from TF_VAR_deployed_branch."
  type        = string
  default     = ""
}

variable "deployed_repo" {
  description = "Repository URL the deployment came from. Auto-filled in CI from TF_VAR_deployed_repo."
  type        = string
  default     = ""
}

variable "loc" {
  description = "Outfix: short Azure region code used in resource names (for example uks)."
  type        = string
  default     = "uks"
}

variable "notify_webhook_url" {
  description = "Webhook the summary is POSTed to; a SecureString workflow parameter riding sensitive_body. The example.com default fails deterministically on purpose, so a drill exercises the failure path without a third-party dependency."
  type        = string
  default     = "https://example.com/soc-notify"
  sensitive   = true
}

variable "regions" {
  description = "Map of short region codes to Azure region slugs."
  type        = map(string)
  default = {
    uks = "uksouth"
    ukw = "ukwest"
    eus = "eastus"
    euw = "westeurope"
  }
}

variable "short" {
  description = "Infix: short product code used in resource names."
  type        = string
  default     = "ldo"
}
