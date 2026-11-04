locals {
  gateway_uses_existing_subnet = !var.api2026_private_lab_enabled && var.gateway_backend_subnet_id != ""
  gateway_has_backend_subnet   = var.api2026_private_lab_enabled || local.gateway_uses_existing_subnet
  gateway_backend_subnet_id    = var.api2026_private_lab_enabled ? azapi_resource.api2026_subnet["gateway-outbound"].id : var.gateway_backend_subnet_id
}

data "azapi_resource" "gateway_backend_subnet" {
  count                  = local.gateway_uses_existing_subnet ? 1 : 0
  type                   = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  resource_id            = var.gateway_backend_subnet_id
  response_export_values = ["properties.delegations"]
}

data "azapi_resource" "gateway_backend_vnet" {
  count                  = local.gateway_uses_existing_subnet ? 1 : 0
  type                   = "Microsoft.Network/virtualNetworks@2024-05-01"
  resource_id            = join("/", slice(split("/", var.gateway_backend_subnet_id), 0, 9))
  response_export_values = ["location"]
}
