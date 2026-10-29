terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13.0"
    }
  }
}

locals {
  bicep_profile = jsondecode(file("${path.module}/bicep-profile.json"))
}

# This entry point owns a separate state; it never adopts the parent root's state.
module "gateway" {
  source = "../"

  gateway_contract          = "2026"
  subscription_id           = var.subscription_id
  environment_name          = var.environment_name
  location                  = var.location
  gateway_location          = var.gateway_location
  gateway_backend_subnet_id = var.gateway_backend_subnet_id
  gateway_access_principals = var.gateway_access_principals
  developer_principal_id    = var.developer_principal_id
  developer_principal_type  = var.developer_principal_type
  model_deployments         = var.model_deployments == null ? local.bicep_profile.model_deployments : var.model_deployments
  model_aliases             = var.model_aliases == null ? local.bicep_profile.model_aliases : var.model_aliases
  tags                      = merge(var.tags, { "gateway-contract" = "api2026gateway" })
}
