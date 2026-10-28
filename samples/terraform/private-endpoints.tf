locals {
  private_endpoints = var.enable_private_networking ? merge({
    gateway = {
      resource_id         = azapi_resource.gateway.id
      group_id            = "Gateway"
      dns_keys            = ["gateway"]
      connection_name     = var.gateway_private_endpoint_manual_approval ? "gateway-manual" : "gateway"
      connection_property = var.gateway_private_endpoint_manual_approval ? "manualPrivateLinkServiceConnections" : "privateLinkServiceConnections"
    }
    models = {
      resource_id         = azapi_resource.models.id
      group_id            = "account"
      dns_keys            = ["cognitiveservices", "openai", "services"]
      connection_name     = "models"
      connection_property = "privateLinkServiceConnections"
    }
    }, var.enable_storage_private_endpoint ? {
    storage = {
      resource_id         = azapi_resource.storage.id
      group_id            = "blob"
      dns_keys            = ["storage"]
      connection_name     = "storage"
      connection_property = "privateLinkServiceConnections"
    }
  } : {}) : {}
}

resource "azapi_resource" "private_endpoint" {
  for_each  = local.private_endpoints
  type      = "Microsoft.Network/privateEndpoints@2024-05-01"
  name      = "${local.names.gateway}-${each.value.connection_name}-pe"
  parent_id = azapi_resource.resource_group["gateway"].id
  location  = local.private_endpoint_locations[each.key]
  tags      = local.tags
  # Body-relative paths cover known targets; unknown IDs also need -replace (see reference).
  replace_triggers_refs = ["properties.${each.value.connection_property}", "properties.subnet"]
  body = {
    properties = {
      subnet = { id = local.private_endpoint_subnet_ids[each.key] }
      (each.value.connection_property) = [{
        name = each.value.connection_name
        properties = {
          privateLinkServiceId = each.value.resource_id
          groupIds             = [each.value.group_id]
        }
      }]
    }
  }
}

data "azapi_resource" "gateway_private_endpoint_connection" {
  count                  = var.enable_private_networking && var.gateway_private_endpoint_manual_approval ? 1 : 0
  type                   = "Microsoft.ApiManagement/service/privateEndpointConnections@2025-09-01-preview"
  name                   = local.private_endpoints["gateway"].connection_name
  parent_id              = azapi_resource.gateway.id
  response_export_values = ["properties.privateEndpoint.id", "properties.privateLinkServiceConnectionState.status"]
  depends_on             = [azapi_resource.private_endpoint["gateway"]]
}

resource "azapi_resource_action" "gateway_private_endpoint_approval" {
  count = var.enable_private_networking && var.gateway_private_endpoint_manual_approval ? 1 : 0
  type  = "Microsoft.ApiManagement/service/privateEndpointConnections@2025-09-01-preview"
  # Keep identity stable when another endpoint defers the connection read.
  resource_id = "${azapi_resource.gateway.id}/privateEndpointConnections/${local.private_endpoints["gateway"].connection_name}"
  method      = data.azapi_resource.gateway_private_endpoint_connection[0].output.properties.privateLinkServiceConnectionState.status == "Approved" ? "GET" : "PUT"
  when        = "apply"
  locks       = [azapi_resource.gateway.id]
  # A non-null body avoids AzAPI's null/unknown plan bug; GET never sends this body.
  body = {
    id = "${azapi_resource.gateway.id}/privateEndpointConnections/${local.private_endpoints["gateway"].connection_name}"
    properties = {
      privateLinkServiceConnectionState = {
        status      = "Approved"
        description = "Approved private gateway connectivity repair"
      }
    }
  }
  depends_on = [azapi_resource.private_endpoint["gateway"]]
  lifecycle {
    replace_triggered_by = [azapi_resource.private_endpoint["gateway"]]
    precondition {
      condition     = lower(data.azapi_resource.gateway_private_endpoint_connection[0].output.properties.privateEndpoint.id) == lower(azapi_resource.private_endpoint["gateway"].id)
      error_message = "Refusing to approve an APIM connection belonging to another private endpoint."
    }
    precondition {
      condition     = contains(["Pending", "Approved"], data.azapi_resource.gateway_private_endpoint_connection[0].output.properties.privateLinkServiceConnectionState.status)
      error_message = "The gateway private connection must be Pending or Approved; investigate rejected or disconnected connections before retrying."
    }
  }
}

resource "azapi_resource" "private_dns_zone_group" {
  for_each  = var.private_dns_zone_group_management == "workload" ? local.private_endpoints : {}
  type      = "Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01"
  name      = "default"
  parent_id = azapi_resource.private_endpoint[each.key].id
  body = {
    properties = {
      privateDnsZoneConfigs = [for key in each.value.dns_keys : {
        name       = key
        properties = { privateDnsZoneId = local.private_dns_zone_ids[key] }
      }]
    }
  }
  depends_on = [azapi_resource_action.gateway_private_endpoint_approval]
}
