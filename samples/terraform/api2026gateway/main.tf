locals {
  default_profile = jsondecode(file("${path.module}/model-profile.json"))
  # Match the typed deprecated-input guard without adding it to the JSON profile.
  default_model_deployments = {
    for key, model in local.default_profile.model_deployments :
    key => merge(model, { content_safety_severity = null })
  }
}

# This entry point owns a separate state; it never adopts the parent root's state.
module "gateway" {
  source = "../"

  gateway_contract                         = "2026"
  subscription_id                          = var.subscription_id
  environment_name                         = var.environment_name
  location                                 = var.location
  gateway_location                         = var.gateway_location
  api2026_resource_group_name              = var.api2026_resource_group_name
  api2026_private_lab_enabled              = var.api2026_private_lab_enabled
  api2026_private_lab_ssh_public_key       = var.api2026_private_lab_ssh_public_key
  gateway_backend_subnet_id                = var.gateway_backend_subnet_id
  standalone_backend_public_network_access = var.standalone_backend_public_network_access
  gateway_access_principals                = var.gateway_access_principals
  developer_principal_id                   = var.developer_principal_id
  developer_principal_type                 = var.developer_principal_type
  model_deployments                        = var.model_deployments == null ? local.default_model_deployments : var.model_deployments
  model_aliases                            = var.model_aliases == null ? local.default_profile.model_aliases : var.model_aliases
  model_allowed_client_cidrs               = var.model_allowed_client_cidrs
  tags                                     = merge(var.tags, { "gateway-contract" = "api2026gateway" })
}
