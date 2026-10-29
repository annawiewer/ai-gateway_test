output "resource_groups" {
  value = module.gateway.resource_groups
}

output "gateway_id" {
  value = module.gateway.gateway_id
}

output "gateway_endpoint" {
  value = module.gateway.gateway_endpoint
}

output "gateway_contract" {
  value = module.gateway.gateway_contract
}

output "gateway_api_versions" {
  value = module.gateway.gateway_api_versions
}

output "gateway_api_key_id" {
  description = "Resource ID only. No runtime credential is returned."
  value       = module.gateway.gateway_api_key_id
}

output "model_deployment_ids" {
  value = module.gateway.model_deployment_ids
}

output "model_api_configuration" {
  value = module.gateway.model_api_configuration
}

output "model_alias_configuration" {
  value = module.gateway.model_alias_configuration
}

output "foundry_models_id" {
  value = module.gateway.foundry_models_id
}

output "project_id" {
  value = module.gateway.project_id
}

output "project_endpoint" {
  value = module.gateway.project_endpoint
}

output "container_registry_endpoint" {
  value = module.gateway.container_registry_endpoint
}

output "storage_account_name" {
  value = module.gateway.storage_account_name
}

output "application_insights_ids" {
  value = module.gateway.application_insights_ids
}

output "gateway_monitoring" {
  value = module.gateway.gateway_monitoring
}
