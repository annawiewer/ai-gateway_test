locals {
  private_dns_zones = var.enable_private_networking ? merge({
    gateway           = "privatelink.azure-api.net"
    cognitiveservices = "privatelink.cognitiveservices.azure.com"
    openai            = "privatelink.openai.azure.com"
    services          = "privatelink.services.ai.azure.com"
    }, var.enable_storage_private_endpoint ? { storage = "privatelink.blob.core.windows.net" } : {},
  var.enable_private_hosted_agent ? { registry = "privatelink.azurecr.io" } : {}) : {}
  private_subnets = local.create_private_network ? merge({
    gateway   = cidrsubnet(var.private_network_address_prefix, 8, 0)
    endpoints = cidrsubnet(var.private_network_address_prefix, 8, 1)
    client    = cidrsubnet(var.private_network_address_prefix, 8, 2)
  }, var.enable_private_hosted_agent ? { agents = cidrsubnet(var.private_network_address_prefix, 8, 3) } : {}) : {}
}

resource "azapi_resource" "private_vnet" {
  count     = local.create_private_network ? 1 : 0
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  name      = "${local.names.gateway}-vnet"
  parent_id = azapi_resource.resource_group["gateway"].id
  location  = var.gateway_location
  tags      = local.tags
  body = {
    properties = { addressSpace = { addressPrefixes = [var.private_network_address_prefix] } }
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "azapi_resource" "private_nsg" {
  for_each  = local.create_private_network ? toset(concat(["gateway", "client"], var.enable_private_hosted_agent ? ["agents"] : [])) : toset([])
  type      = "Microsoft.Network/networkSecurityGroups@2024-05-01"
  name      = "${local.names.gateway}-${each.key}-nsg"
  parent_id = azapi_resource.resource_group["gateway"].id
  location  = var.gateway_location
  tags      = local.tags
  body = {
    properties = {
      securityRules = each.key == "client" ? [{
        name = "DenyAllInbound"
        properties = {
          priority                 = 100
          direction                = "Inbound"
          access                   = "Deny"
          protocol                 = "*"
          sourcePortRange          = "*"
          destinationPortRange     = "*"
          sourceAddressPrefix      = "*"
          destinationAddressPrefix = "*"
        }
        }] : [for index, service in(each.key == "agents" ? ["AzureActiveDirectory", "AzureResourceManager", "AzureContainerRegistry", "AzureMonitor"] : ["Storage", "AzureKeyVault"]) : {
        name = "Allow${service}Https"
        properties = {
          priority                 = 100 + index
          direction                = "Outbound"
          access                   = "Allow"
          protocol                 = "Tcp"
          sourcePortRange          = "*"
          destinationPortRange     = "443"
          sourceAddressPrefix      = "VirtualNetwork"
          destinationAddressPrefix = service
        }
      }]
    }
  }
}

resource "azapi_resource" "private_subnet" {
  for_each  = local.private_subnets
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = each.key
  parent_id = azapi_resource.private_vnet[0].id
  locks     = [azapi_resource.private_vnet[0].id]
  body = {
    properties = merge(
      { addressPrefix = each.value },
      each.key == "endpoints" ? { privateEndpointNetworkPolicies = "Disabled" } : {},
      each.key != "endpoints" ? {
        networkSecurityGroup = { id = azapi_resource.private_nsg[each.key].id }
      } : {},
      contains(["gateway", "agents"], each.key) ? {
        delegations = [{
          name       = "${each.key}-integration"
          properties = { serviceName = each.key == "agents" ? "Microsoft.App/environments" : "Microsoft.Web/serverFarms" }
        }]
      } : {},
      # Only the isolated PoC client uses default outbound internet for its VM agent.
      each.key == "client" ? { defaultOutboundAccess = true } : {}
    )
  }
}

resource "azapi_resource" "private_dns_zone" {
  for_each  = local.create_private_network ? local.private_dns_zones : {}
  type      = "Microsoft.Network/privateDnsZones@2020-06-01"
  name      = each.value
  parent_id = azapi_resource.resource_group["gateway"].id
  location  = "global"
  tags      = local.tags
  body      = { properties = {} }
}

resource "azapi_resource" "private_dns_link" {
  for_each  = local.create_private_network ? local.private_dns_zones : {}
  type      = "Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01"
  name      = "gateway-vnet"
  parent_id = azapi_resource.private_dns_zone[each.key].id
  location  = "global"
  body = {
    properties = {
      registrationEnabled = false
      virtualNetwork      = { id = azapi_resource.private_vnet[0].id }
    }
  }
}
