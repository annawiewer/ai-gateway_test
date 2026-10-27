locals {
  create_private_network      = var.enable_private_networking && var.private_network_mode == "create"
  private_subnet_id_pattern   = "(?i)^/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$"
  private_dns_zone_id_pattern = "(?i)^/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/[^/]+$"
  private_endpoint_keys = concat(
    ["gateway", "models"],
    var.enable_storage_private_endpoint ? ["storage"] : [],
    var.enable_private_hosted_agent ? ["agents", "registry"] : []
  )
  existing_private_subnet_ids = var.enable_private_networking && var.private_network_mode == "existing" && var.existing_private_network != null ? merge(
    { gateway = var.existing_private_network.gateway_subnet_id },
    { for key in local.private_endpoint_keys : "endpoint_${key}" => lookup(var.existing_private_network.endpoint_subnet_ids, key, "") },
    var.enable_private_hosted_agent ? { agents = var.existing_private_network.agent_subnet_id } : {},
    var.enable_private_test_client ? { client = var.existing_private_network.client_subnet_id } : {}
  ) : {}
}

data "azapi_resource" "existing_private_vnet" {
  for_each               = local.existing_private_subnet_ids
  type                   = "Microsoft.Network/virtualNetworks@2024-05-01"
  resource_id            = try(join("/", slice(split("/", each.value), 0, 9)), "")
  response_export_values = ["location"]
  lifecycle {
    postcondition {
      condition = each.key == "gateway" ? try(lower(self.output.location) == lower(var.gateway_location), false) : (
        each.key == "agents" ? try(lower(self.output.location) == lower(var.location), false) : true
      )
      error_message = "An existing gateway/agent integration VNet must be in the corresponding service region."
    }
  }
}

data "azapi_resource" "existing_private_subnet" {
  for_each    = local.existing_private_subnet_ids
  type        = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  resource_id = each.value
  response_export_values = {
    address_prefixes          = "properties.addressPrefixes || [properties.addressPrefix]"
    delegations               = "properties.delegations[].properties.serviceName || `[]`"
    network_security_group_id = "properties.networkSecurityGroup.id"
  }
  depends_on = [data.azapi_resource.existing_private_vnet]
  lifecycle {
    postcondition {
      condition = try(
        length(self.output.address_prefixes) > 0 &&
        alltrue([for prefix in self.output.address_prefixes : can(cidrnetmask(prefix))]),
        false
      )
      error_message = "Existing subnet metadata must contain valid IPv4 address prefixes; do not infer them from the sample address space."
    }
    postcondition {
      condition = each.key != "gateway" || (
        try(contains(self.output.delegations, "Microsoft.Web/serverFarms"), false) &&
        alltrue([for prefix in try(compact(self.output.address_prefixes), []) : try(tonumber(split("/", prefix)[1]) <= 27, false)])
      )
      error_message = "The existing gateway subnet needs Microsoft.Web/serverFarms delegation and at least a /27 IPv4 prefix."
    }
    postcondition {
      condition     = each.key != "gateway" || try(trimspace(self.output.network_security_group_id) != "", false)
      error_message = "The existing gateway integration subnet must have a network security group attached. Ask the platform owner to associate the approved NSG and verify its outbound rules, then plan again. Existing mode never creates or changes that NSG."
    }
    postcondition {
      condition = each.key != "agents" || (
        try(contains(self.output.delegations, "Microsoft.App/environments"), false) &&
        alltrue([for prefix in try(compact(self.output.address_prefixes), []) :
          try(tonumber(split("/", prefix)[1]) <= 27, false) &&
          alltrue([for offset in [0, -1] :
            can(regex("^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)", cidrhost(prefix, offset)))
          ])
        ])
      )
      error_message = "The existing agent subnet needs Microsoft.App/environments delegation, at least /27, and IPv4 address space wholly within an RFC1918 range supported by this sample."
    }
    postcondition {
      condition     = (!startswith(each.key, "endpoint_") && each.key != "client") || try(length(self.output.delegations) == 0, false)
      error_message = "Existing private endpoint and test-client subnets must not be delegated integration subnets."
    }
  }
}

locals {
  private_gateway_subnet_id = var.enable_private_networking ? (
    local.create_private_network ? azapi_resource.private_subnet["gateway"].id : try(data.azapi_resource.existing_private_subnet["gateway"].resource_id, null)
  ) : null
  private_agent_subnet_id = var.enable_private_hosted_agent ? (
    local.create_private_network ? azapi_resource.private_subnet["agents"].id : try(data.azapi_resource.existing_private_subnet["agents"].resource_id, null)
  ) : null
  private_client_subnet_id = var.enable_private_test_client ? (
    local.create_private_network ? azapi_resource.private_subnet["client"].id : try(data.azapi_resource.existing_private_subnet["client"].resource_id, null)
  ) : null
  private_client_location = var.private_network_mode == "existing" && var.enable_private_test_client ? try(
    data.azapi_resource.existing_private_vnet["client"].output.location, null
  ) : var.gateway_location
  private_endpoint_subnet_ids = var.enable_private_networking ? {
    for key in local.private_endpoint_keys : key => local.create_private_network ? azapi_resource.private_subnet["endpoints"].id : try(
      data.azapi_resource.existing_private_subnet["endpoint_${key}"].resource_id, null
    )
  } : {}
  private_endpoint_locations = var.enable_private_networking ? {
    for key in local.private_endpoint_keys : key => local.create_private_network ? var.gateway_location : try(
      data.azapi_resource.existing_private_vnet["endpoint_${key}"].output.location, null
    )
  } : {}
  private_endpoint_subnet_prefixes = var.enable_private_networking ? {
    for key in local.private_endpoint_keys : key => local.create_private_network ? [local.private_subnets["endpoints"]] : try(
      compact(data.azapi_resource.existing_private_subnet["endpoint_${key}"].output.address_prefixes), []
    )
  } : {}
  private_dns_zone_ids = {
    for key in keys(local.private_dns_zones) : key => local.create_private_network ? azapi_resource.private_dns_zone[key].id : try(
      var.existing_private_network.private_dns_zone_ids[key], null
    )
  }
}
