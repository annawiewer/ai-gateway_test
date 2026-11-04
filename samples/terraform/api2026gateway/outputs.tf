output "resource_groups" {
  description = "Actual group names keyed by workload; exact-name mode maps all three to one owned group."
  value       = module.gateway.resource_groups
}

output "gateway_id" {
  description = "Standalone gateway ARM resource ID for explicitly scoped management checks."
  value       = module.gateway.gateway_id
}

output "gateway_endpoint" {
  description = "Service-returned gateway endpoint; authentication and runtime acceptance are separate checks."
  value       = module.gateway.gateway_endpoint
}

output "gateway_contract" {
  description = "Selected contract, resource type and optional outbound subnet; not proof of private ingress."
  value       = module.gateway.gateway_contract
}

output "gateway_api_versions" {
  description = "Exact management API versions, including the intentionally retained 2025 telemetry contract."
  value       = module.gateway.gateway_api_versions
}

output "gateway_api_key_id" {
  description = "Resource ID only. No runtime credential is returned."
  value       = module.gateway.gateway_api_key_id
}

output "backend_public_network_access" {
  description = "Requested backend access settings, not live private-connectivity or gateway-ingress proof."
  value       = module.gateway.backend_public_network_access
}

output "model_deployment_ids" {
  description = "Foundry deployment ARM IDs keyed by the model deployment names."
  value       = module.gateway.model_deployment_ids
}

output "model_api_configuration" {
  description = "Model API formats and endpoints for checking client compatibility before inference."
  value       = module.gateway.model_api_configuration
}

output "model_alias_configuration" {
  description = "Callable aliases, backend order and shared API metadata; alias ARM keys differ from callable names."
  value       = module.gateway.model_alias_configuration
}

output "foundry_models_id" {
  description = "Dedicated model-serving Foundry account ARM ID; API2026 enables project management without creating a project on this account."
  value       = module.gateway.foundry_models_id
}

output "project_id" {
  description = "Foundry project ARM ID for a separately deployed agent application."
  value       = module.gateway.project_id
}

output "project_endpoint" {
  description = "Foundry project data-plane endpoint; creating the project does not deploy an agent."
  value       = module.gateway.project_endpoint
}

output "container_registry_endpoint" {
  description = "Registry login server for separately built and published agent images."
  value       = module.gateway.container_registry_endpoint
}

output "storage_account_name" {
  description = "Agent project artifact-storage account name."
  value       = module.gateway.storage_account_name
}

output "application_insights_ids" {
  description = "Separate gateway and agent Application Insights resource IDs."
  value       = module.gateway.application_insights_ids
}

output "gateway_monitoring" {
  description = "Nonsecret Application Insights exporter/destination metadata, not evidence of telemetry delivery."
  value       = module.gateway.gateway_monitoring
}

output "api2026_private_lab" {
  description = "Owned private-lab inventory and public client identity metadata, not runtime/private-ingress proof. Null outside the opt-in lab."
  value       = module.gateway.api2026_private_lab
}
