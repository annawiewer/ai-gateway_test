resource "azapi_resource" "gateway" {
  # AzAPI 2.13 does not yet include aigateways; keep legacy schema validation on.
  schema_validation_enabled = !local.gateway_is_2026
  type                      = "${local.gateway_type}@${local.gateway_api_version}"
  name                      = local.names.gateway
  parent_id                 = azapi_resource.resource_group["gateway"].id
  location                  = var.gateway_location
  tags                      = local.tags
  identity { type = "SystemAssigned" }
  # Selecting an object preserves number/null types and partially unknown subnet IDs.
  body = {
    "2026" = {
      properties = !local.gateway_has_backend_subnet ? {} : {
        backend = { subnet = { id = local.gateway_backend_subnet_id } }
      }
    }
    legacy = {
      sku = { name = "AIGateway", capacity = 1 }
      properties = {
        publisherEmail      = var.publisher_email
        publisherName       = var.publisher_name
        publicNetworkAccess = var.gateway_public_network_access
        virtualNetworkType  = var.enable_private_networking ? "External" : "None"
        virtualNetworkConfiguration = var.enable_private_networking ? {
          subnetResourceId = local.private_gateway_subnet_id
        } : null
      }
    }
  }[var.gateway_contract]
  response_export_values = local.gateway_is_2026 ? ["properties.frontend.defaultHostname"] : ["properties.gatewayUrl"]
  create_headers         = local.gateway_is_2026 ? { "If-None-Match" = "*" } : {}
  replace_triggers_refs  = local.gateway_is_2026 ? ["properties.backend"] : []
  lifecycle {
    prevent_destroy = true
    precondition {
      condition = !local.gateway_uses_existing_subnet || try(contains([
        for delegation in data.azapi_resource.gateway_backend_subnet[0].output.properties.delegations :
        lower(delegation.properties.serviceName)
      ], "microsoft.app/environments"), false)
      error_message = "The existing 2026 backend subnet must be delegated to Microsoft.App/environments. The workload does not modify platform-owned subnet configuration."
    }
    precondition {
      condition = !local.gateway_uses_existing_subnet || try(
        lower(replace(data.azapi_resource.gateway_backend_vnet[0].output.location, " ", "")) == lower(replace(var.gateway_location, " ", "")),
        false
      )
      error_message = "The 2026 backend subnet VNet must be in gateway_location."
    }
  }
  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
  depends_on = [azapi_resource.private_dns_link, data.azapi_resource.existing_private_subnet, azapi_resource.api2026_dns_link]
}

resource "azapi_resource" "connector_gateway" {
  count = local.gateway_is_2026 ? 0 : 1
  # This preview type is not yet present in AzAPI's bundled schema.
  schema_validation_enabled = false
  type                      = "Microsoft.Web/connectorGateways@2026-05-01-preview"
  name                      = local.names.gateway
  parent_id                 = azapi_resource.resource_group["gateway"].id
  location                  = var.gateway_location
  body                      = { properties = {} }
  depends_on                = [azapi_resource.gateway]
}

moved {
  from = azapi_resource.connector_gateway
  to   = azapi_resource.connector_gateway[0]
}

locals {
  # The AIGateway service creates its default workspace; do not manage it twice.
  gateway_workspace_id      = "${azapi_resource.gateway.id}/workspaces/default"
  gateway_hostname          = try(trimspace(azapi_resource.gateway.output.properties.frontend.defaultHostname), "")
  gateway_url               = try(trimspace(azapi_resource.gateway.output.properties.gatewayUrl), "")
  gateway_frontend_endpoint = local.gateway_hostname == "" ? "" : "https://${local.gateway_hostname}"
  gateway_endpoint = local.gateway_is_2026 ? local.gateway_frontend_endpoint : (
    local.gateway_url != "" ? local.gateway_url : local.gateway_frontend_endpoint
  )
}

resource "azapi_resource" "runtime_api_key" {
  # This preview type is not yet present in AzAPI's bundled schema.
  schema_validation_enabled = false
  type                      = "${local.gateway_type}/apiKeys@${local.gateway_api_version}"
  name                      = "default"
  parent_id                 = azapi_resource.gateway.id
  body                      = { properties = { displayName = "All APIs subscription" } }
  response_export_values    = []
}
