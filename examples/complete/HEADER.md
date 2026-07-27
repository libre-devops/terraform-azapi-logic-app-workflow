<!--
  Header for the complete example README. Edit this file, then run `just docs`
  (or ./Sort-LdoTerraform.ps1 -IncludeExamples) to regenerate the section between the markers.
  The example's main.tf is embedded into the README automatically (see .terraform-docs.yml).
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="200">
    </picture>
  </a>
</div>

# Complete example

The full estate shape: one playbook deployed whole from a portal-shaped template (scalar tokens
only), typed parameter values including a SecureString riding the provider's write-only
`sensitive_body`, the generated `$connections` parameter against a real V1 Sentinel connection
with managed identity auth (`parameterValueType = "Alternative"`, the only combination Consumption
accepts), diagnostics to a Log Analytics workspace, an AAD open authentication policy on the
trigger, and the trigger's callback URL surfaced for an action group receiver.

Everything here is free at rest (the workflow only bills per action execution and nothing invokes
it), so the example is safe to apply; `just e2e complete` applies then always destroys it, and the
CI self-test does the same on manual dispatch.

[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
