locals {
  gateway_is_2026     = var.gateway_contract == "2026"
  gateway_type        = local.gateway_is_2026 ? "Microsoft.ApiManagement/aigateways" : "Microsoft.ApiManagement/service"
  gateway_api_version = local.gateway_is_2026 ? "2026-09-01-preview" : "2025-09-01-preview"
  # Telemetry retains its separate pin; a 2026 exporter contract is not established.
  gateway_telemetry_api_version = "2025-09-01-preview"
  # Tool servers keep a separate pin: the blue-octopus reference registers them with this preview version.
  gateway_tool_server_api_version = "2025-09-01-preview"
  # The gateway-wide policy PATCH uses the preview version from the Azure/aigateway gateway baselines lab.
  gateway_policy_api_version      = "2025-09-01-preview"
  api2026_single_resource_group   = local.gateway_is_2026 && var.api2026_resource_group_name != null
  api2026_existing_resource_group = local.api2026_single_resource_group && var.api2026_existing_resource_group
  resource_group_keys             = { for key in ["gateway", "models", "agents"] : key => local.gateway_is_2026 && !local.api2026_single_resource_group ? key : "gateway" }
  # Exactly one source supplies each physical group: owned groups, or the existing group in its mode.
  resource_group_ids = merge(
    { for key, group in azapi_resource.resource_group : key => group.id },
    { for group in data.azapi_resource.existing_resource_group : "gateway" => group.id }
  )
  resource_group_names = merge(
    { for key, group in azapi_resource.resource_group : key => group.name },
    { for group in data.azapi_resource.existing_resource_group : "gateway" => var.api2026_resource_group_name }
  )
  subscription_scope = "/subscriptions/${var.subscription_id}"
  resource_token     = substr(sha256("${var.subscription_id}:${var.environment_name}:${var.location}${local.gateway_is_2026 ? ":api2026gateway" : ""}"), 0, 12)
  backend_token      = var.backend_revision == "" ? local.resource_token : substr(sha256("${local.resource_token}:${var.backend_revision}"), 0, 12)
  tags               = merge(var.tags, { environment = var.environment_name })
  backend_network_access = {
    models   = coalesce(var.standalone_backend_public_network_access, var.models_public_network_access)
    storage  = coalesce(var.standalone_backend_public_network_access, var.storage_public_network_access)
    agents   = coalesce(var.standalone_backend_public_network_access, "Enabled")
    registry = coalesce(var.standalone_backend_public_network_access, "Enabled")
  }
  backend_monitoring_access = var.standalone_backend_public_network_access == null ? {} : {
    publicNetworkAccessForIngestion = var.standalone_backend_public_network_access
    publicNetworkAccessForQuery     = var.standalone_backend_public_network_access
  }
  names = {
    gateway  = "aigw-${local.resource_token}"
    models   = "aimodels-${local.backend_token}"
    agents   = "aiagents-${local.backend_token}"
    project  = "proj-${local.backend_token}"
    storage  = "st${local.backend_token}"
    registry = "acr${local.backend_token}"
  }
}

resource "azapi_resource" "resource_group" {
  # The exact-name and existing-group modes are for fresh state, not migration of deployed groups.
  for_each  = toset(local.api2026_existing_resource_group ? [] : local.api2026_single_resource_group ? ["gateway"] : local.gateway_is_2026 || var.retain_legacy_resource_groups ? ["gateway", "models", "agents"] : ["gateway"])
  type      = "Microsoft.Resources/resourceGroups@2021-04-01"
  name      = local.api2026_single_resource_group ? var.api2026_resource_group_name : "rg-${var.environment_name}-${local.resource_token}-${each.key}"
  parent_id = local.subscription_scope
  location  = var.location
  tags      = local.tags
  body      = { properties = {} }
}

data "azapi_resource" "existing_resource_group" {
  # Read-only lookup: Terraform never creates, tags or deletes a reused group.
  count     = local.api2026_existing_resource_group ? 1 : 0
  type      = "Microsoft.Resources/resourceGroups@2021-04-01"
  name      = var.api2026_resource_group_name
  parent_id = local.subscription_scope
}
