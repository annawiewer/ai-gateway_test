locals {
  api2026_lab_keys = var.api2026_private_lab_enabled ? toset(["lab"]) : toset([])
  api2026_cognitive_zones = [
    "privatelink.cognitiveservices.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.services.ai.azure.com"
  ]
  api2026_monitor_zones = [
    "privatelink.monitor.azure.com",
    "privatelink.oms.opinsights.azure.com",
    "privatelink.ods.opinsights.azure.com",
    "privatelink.agentsvc.azure-automation.net",
    "privatelink.blob.core.windows.net"
  ]
  api2026_dns_zones = var.api2026_private_lab_enabled ? toset(concat(
    local.api2026_cognitive_zones, local.api2026_monitor_zones, ["privatelink.azurecr.io"]
  )) : toset([])
  api2026_monitor_targets = var.api2026_private_lab_enabled ? {
    gateway-logs     = azapi_resource.logs["gateway"].id
    gateway-insights = azapi_resource.insights["gateway"].id
    agents-logs      = azapi_resource.logs["agents"].id
    agents-insights  = azapi_resource.insights["agents"].id
  } : {}
  api2026_endpoint_targets = var.api2026_private_lab_enabled ? {
    blob = {
      id    = azapi_resource.storage.id
      group = "blob"
      zones = ["privatelink.blob.core.windows.net"]
    }
    models = {
      id    = azapi_resource.models.id
      group = "account"
      zones = local.api2026_cognitive_zones
    }
    agents = {
      id    = azapi_resource.agents.id
      group = "account"
      zones = local.api2026_cognitive_zones
    }
    registry = {
      id    = azapi_resource.registry.id
      group = "registry"
      zones = ["privatelink.azurecr.io"]
    }
    monitor = {
      id    = azapi_resource.api2026_ampls["lab"].id
      group = "azuremonitor"
      zones = local.api2026_monitor_zones
    }
  } : {}
  api2026_client_outbound = {
    dns                 = { priority = 100, protocol = "*", target = "168.63.129.16", ports = ["53"] }
    platform            = { priority = 110, protocol = "Tcp", target = "168.63.129.16", ports = ["80", "32526"] }
    identity            = { priority = 120, protocol = "Tcp", target = "169.254.169.254", ports = ["80"] }
    private-https       = { priority = 130, protocol = "Tcp", target = "10.244.1.0/24", ports = ["443"] }
    azure-control-https = { priority = 140, protocol = "Tcp", target = "AzureCloud", ports = ["443"] }
  }
}

resource "azapi_resource" "api2026_vnet" {
  for_each  = local.api2026_lab_keys
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  name      = "vnet-${local.resource_token}-lab"
  parent_id = local.resource_group_ids["gateway"]
  location  = var.location
  tags      = local.tags
  body = {
    properties = {
      addressSpace = { addressPrefixes = ["10.244.0.0/16"] }
      dhcpOptions  = { dnsServers = [] }
    }
  }
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "api2026_nsg" {
  for_each  = var.api2026_private_lab_enabled ? toset(["client", "gateway"]) : toset([])
  type      = "Microsoft.Network/networkSecurityGroups@2024-05-01"
  name      = "nsg-${local.resource_token}-${each.key}"
  parent_id = local.resource_group_ids["gateway"]
  location  = var.location
  tags      = local.tags
  body = {
    properties = {
      securityRules = {
        gateway = []
        client = concat(
          [for name, rule in local.api2026_client_outbound : {
            name = "allow-${name}"
            properties = {
              priority                 = rule.priority
              access                   = "Allow"
              direction                = "Outbound"
              protocol                 = rule.protocol
              sourcePortRange          = "*"
              sourceAddressPrefix      = "*"
              destinationAddressPrefix = rule.target
              destinationPortRanges    = rule.ports
            }
          }],
          [for direction in ["Inbound", "Outbound"] : {
            name = "deny-other-${lower(direction)}"
            properties = {
              priority                 = 4096
              access                   = "Deny"
              direction                = direction
              protocol                 = "*"
              sourcePortRange          = "*"
              sourceAddressPrefix      = "*"
              destinationAddressPrefix = "*"
              destinationPortRange     = "*"
            }
          }]
        )
      }[each.key]
    }
  }
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "api2026_nat_ip" {
  for_each  = var.api2026_private_lab_enabled ? toset(["client"]) : toset([])
  type      = "Microsoft.Network/publicIPAddresses@2024-05-01"
  name      = "pip-${local.resource_token}-egress"
  parent_id = local.resource_group_ids["gateway"]
  location  = var.location
  tags      = local.tags
  body = {
    sku = { name = "Standard", tier = "Regional" }
    properties = {
      publicIPAllocationMethod = "Static"
      publicIPAddressVersion   = "IPv4"
    }
  }
  response_export_values = ["properties.ipAddress"]
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "api2026_nat" {
  for_each  = var.api2026_private_lab_enabled ? toset(["client"]) : toset([])
  type      = "Microsoft.Network/natGateways@2024-05-01"
  name      = "nat-${local.resource_token}-client"
  parent_id = local.resource_group_ids["gateway"]
  location  = var.location
  tags      = local.tags
  body = {
    sku = { name = "Standard" }
    properties = {
      idleTimeoutInMinutes = 4
      publicIpAddresses    = [{ id = azapi_resource.api2026_nat_ip[each.key].id }]
    }
  }
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "api2026_subnet" {
  for_each  = var.api2026_private_lab_enabled ? toset(["gateway-outbound", "private-endpoints", "verification-client"]) : toset([])
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = each.key
  parent_id = azapi_resource.api2026_vnet["lab"].id
  locks     = [azapi_resource.api2026_vnet["lab"].id]
  body = {
    properties = {
      gateway-outbound = {
        addressPrefix        = "10.244.0.0/24"
        networkSecurityGroup = { id = azapi_resource.api2026_nsg["gateway"].id }
        delegations = [{
          name       = "gateway-integration"
          properties = { serviceName = "Microsoft.App/environments" }
        }]
      }
      private-endpoints = {
        addressPrefix                  = "10.244.1.0/24"
        delegations                    = []
        privateEndpointNetworkPolicies = "Disabled"
      }
      verification-client = {
        addressPrefix         = "10.244.2.0/24"
        defaultOutboundAccess = false
        natGateway            = { id = azapi_resource.api2026_nat["client"].id }
        networkSecurityGroup  = { id = azapi_resource.api2026_nsg["client"].id }
      }
    }[each.key]
  }
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "api2026_ampls" {
  for_each  = local.api2026_lab_keys
  type      = "Microsoft.Insights/privateLinkScopes@2021-09-01"
  name      = "ampls-${local.resource_token}"
  parent_id = local.resource_group_ids["gateway"]
  location  = "global"
  tags      = local.tags
  body = {
    properties = {
      accessModeSettings = {
        ingestionAccessMode = "PrivateOnly"
        queryAccessMode     = "PrivateOnly"
        exclusions          = []
      }
    }
  }
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "api2026_monitor_resource" {
  for_each  = local.api2026_monitor_targets
  type      = "Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01"
  name      = each.key
  parent_id = azapi_resource.api2026_ampls["lab"].id
  locks     = [azapi_resource.api2026_ampls["lab"].id]
  body      = { properties = { linkedResourceId = lower(each.value) } }
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "api2026_private_endpoint" {
  for_each  = local.api2026_endpoint_targets
  type      = "Microsoft.Network/privateEndpoints@2024-05-01"
  name      = "pe-${local.resource_token}-${each.key}"
  parent_id = local.resource_group_ids["gateway"]
  location  = var.location
  tags      = local.tags
  locks     = [azapi_resource.api2026_subnet["private-endpoints"].id]
  body = {
    properties = {
      subnet = { id = azapi_resource.api2026_subnet["private-endpoints"].id }
      privateLinkServiceConnections = [{
        name = each.key
        properties = {
          privateLinkServiceId = each.value.id
          groupIds             = [each.value.group]
        }
      }]
    }
  }
  response_export_values = ["properties.privateLinkServiceConnections", "properties.networkInterfaces", "properties.customDnsConfigs"]
  depends_on             = [azapi_resource.api2026_monitor_resource]
  lifecycle { prevent_destroy = true }
  timeouts { create = "20m" }
}

resource "azapi_resource" "api2026_dns_zone" {
  for_each  = local.api2026_dns_zones
  type      = "Microsoft.Network/privateDnsZones@2020-06-01"
  name      = each.key
  parent_id = local.resource_group_ids["gateway"]
  location  = "global"
  tags      = local.tags
  body      = { properties = {} }
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "api2026_dns_group" {
  for_each  = local.api2026_endpoint_targets
  type      = "Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01"
  name      = "default"
  parent_id = azapi_resource.api2026_private_endpoint[each.key].id
  locks     = [azapi_resource.api2026_private_endpoint[each.key].id]
  body = {
    properties = {
      privateDnsZoneConfigs = [for zone in each.value.zones : {
        name       = replace(zone, ".", "-")
        properties = { privateDnsZoneId = azapi_resource.api2026_dns_zone[zone].id }
      }]
    }
  }
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "api2026_dns_link" {
  for_each  = local.api2026_dns_zones
  type      = "Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01"
  name      = "lab"
  parent_id = azapi_resource.api2026_dns_zone[each.key].id
  location  = "global"
  tags      = local.tags
  locks     = [azapi_resource.api2026_vnet["lab"].id]
  body = {
    properties = {
      registrationEnabled = false
      virtualNetwork      = { id = azapi_resource.api2026_vnet["lab"].id }
    }
  }
  depends_on = [azapi_resource.api2026_dns_group]
  lifecycle { prevent_destroy = true }
}
