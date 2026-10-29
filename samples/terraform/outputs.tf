output "resource_group_name" {
  description = "Gateway application group. Legacy shares it across workloads; use resource_groups for the separate 2026 layout."
  value       = azapi_resource.resource_group["gateway"].name
}

output "resource_groups" {
  description = "Actual group names for gateway, models and agents. Legacy shares one group; 2026 separates the three workloads like Bicep."
  value       = { for key, group in local.resource_group_keys : key => azapi_resource.resource_group[group].name }
}

output "gateway_id" {
  description = "ARM resource ID of the selected gateway resource family."
  value       = azapi_resource.gateway.id
}

output "gateway_endpoint" {
  description = "Runtime endpoint returned by the gateway service."
  value       = local.gateway_endpoint
}

output "gateway_api_versions" {
  description = "Exact management API versions. The 2026 variant intentionally retains the Bicep 2025 telemetry exporter contract."
  value = {
    gateway   = local.gateway_api_version
    catalog   = local.gateway_api_version
    aliases   = local.gateway_api_version
    api_keys  = local.gateway_api_version
    telemetry = local.gateway_telemetry_api_version
  }
}

output "gateway_contract" {
  description = "Selected contract, resource type and outbound subnet; not proof of live API or private ingress availability."
  value = {
    name              = var.gateway_contract
    resource_type     = local.gateway_type
    backend_subnet_id = var.gateway_backend_subnet_id == "" ? null : var.gateway_backend_subnet_id
  }
}

output "gateway_api_key_id" {
  description = "API key resource ID only; no runtime key value is exported."
  value       = azapi_resource.runtime_api_key.id
}

output "model_deployment_ids" {
  description = "Model deployment ARM IDs keyed by the names registered in the gateway."
  value       = { for key, deployment in azapi_resource.model_deployment : key => deployment.id }
}

output "model_api_configuration" {
  description = "Non-secret API metadata used to check compatibility before running the sample's chat-completions probes."
  value = { for key, model in var.model_deployments : key => {
    api_format = model.api_format
    endpoints  = model.endpoints
  } }
}

output "model_alias_configuration" {
  description = "Callable aliases, catalog routes and common API metadata. Alias ARM names and deployment names need not be the same."
  value = { for key, alias in local.gateway_aliases : key => {
    alias_name = alias.alias_name
    api_format = try(var.model_deployments[alias.backend_models[0].deployment].api_format, null)
    endpoints = try(sort(tolist(setintersection([
      for backend in alias.backend_models : toset(var.model_deployments[backend.deployment].endpoints)
    ]...))), [])
    backend_models = alias.backend_models
  } }
}

output "foundry_models_id" {
  description = "Dedicated Foundry model account ARM ID."
  value       = azapi_resource.models.id
}

output "project_id" {
  description = "Foundry hosted-agent project ARM ID."
  value       = azapi_resource.project.id
}

output "project_endpoint" {
  description = "Foundry project data-plane endpoint."
  value       = "https://${local.names.agents}.services.ai.azure.com/api/projects/${local.names.project}"
}

output "container_registry_endpoint" {
  description = "Registry login server for separately built hosted-agent images."
  value       = azapi_resource.registry.output.properties.loginServer
}

output "storage_account_name" {
  description = "Storage account for project artifacts."
  value       = azapi_resource.storage.name
}

output "application_insights_ids" {
  description = "Separate Application Insights resource IDs for gateway telemetry and agent tracing."
  value       = { for key, insights in azapi_resource.insights : key => insights.id }
}

output "gateway_monitoring" {
  description = "Nonsecret exporter metadata. Legacy uses OTLP/DCR; 2026 matches Bicep applicationInsights and does not create an OTLP publisher role."
  value = merge(local.gateway_is_2026 ? {} : local.gateway_monitoring, {
    kind             = local.gateway_is_2026 ? "applicationInsights" : "OpenTelemetry"
    insights_id      = azapi_resource.insights["gateway"].id
    log_analytics_id = azapi_resource.logs["gateway"].id
  })
}

output "private_endpoint_ids" {
  description = "Gateway, model and optional Blob, private agent and registry private endpoint IDs."
  value = merge(
    { for key, endpoint in azapi_resource.private_endpoint : key => endpoint.id },
    { for key, endpoint in azapi_resource.private_agent_endpoint : key => endpoint.id }
  )
}

output "private_network_configuration" {
  description = "Non-secret network ownership and actual subnet/DNS metadata. Existing foundations remain platform-owned; this output is not proof of resolver or firewall readiness."
  value = var.enable_private_networking ? {
    mode                      = var.private_network_mode
    gateway_subnet_id         = local.private_gateway_subnet_id
    endpoint_subnet_ids       = local.private_endpoint_subnet_ids
    endpoint_subnet_prefixes  = local.private_endpoint_subnet_prefixes
    private_dns_zone_ids      = local.private_dns_zone_ids
    dns_zone_group_management = var.private_dns_zone_group_management
    agent_subnet_id           = local.private_agent_subnet_id
    client_subnet_id          = local.private_client_subnet_id
  } : null
}

output "private_hosted_agent" {
  description = "Additional private project setup, not proof of a deployed agent. Original project_id/project_endpoint remain unchanged. No keys are exported."
  value = var.enable_private_hosted_agent ? {
    account_id                     = azapi_resource.private_agents[0].id
    project_id                     = azapi_resource.private_project[0].id
    project_endpoint               = "https://${local.private_agent_name}.services.ai.azure.com/api/projects/${local.private_project_name}"
    project_principal_id           = azapi_resource.private_project[0].identity[0].principal_id
    subnet_id                      = local.private_agent_subnet_id
    gateway_endpoint               = local.gateway_endpoint
    registry_endpoint              = azapi_resource.registry.output.properties.loginServer
    key_reader_role_definition_id  = var.enable_private_test_client ? azapi_resource.private_test_key_role[0].id : azapi_resource.private_agent_key_role[0].id
    runtime_key_binding_configured = var.private_hosted_agent_runtime_principal_id != ""
  } : null
}
output "private_test_vm_id" {
  description = "Optional private test VM ID. Start/deallocate separately; power state is not Terraform configuration."
  value       = var.enable_private_test_client ? azapi_resource.private_test_vm[0].id : null
}

output "private_probe_configuration" {
  description = "Non-secret inputs for scripts/private-path-probe.py on the optional test VM."
  value = var.enable_private_test_client ? merge({
    gateway_id               = azapi_resource.gateway.id
    gateway_endpoint         = local.gateway_endpoint
    model_endpoint           = azapi_resource.models.output.properties.endpoint
    model_names              = keys(var.model_deployments)
    private_endpoint_subnet  = var.private_network_mode == "create" ? local.private_subnets["endpoints"] : null
    private_endpoint_subnets = local.private_endpoint_subnet_prefixes
    }, var.enable_storage_private_endpoint ? {
    storage_endpoint = azapi_resource.storage.output.properties.primaryEndpoints.blob
  } : {}) : null
}
