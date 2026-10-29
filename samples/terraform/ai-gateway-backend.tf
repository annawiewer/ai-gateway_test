data "azapi_resource" "gateway_backend_subnet" {
  count                  = var.gateway_backend_subnet_id == "" ? 0 : 1
  type                   = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  resource_id            = var.gateway_backend_subnet_id
  response_export_values = ["properties.delegations"]
}

data "azapi_resource" "gateway_backend_vnet" {
  count                  = var.gateway_backend_subnet_id == "" ? 0 : 1
  type                   = "Microsoft.Network/virtualNetworks@2024-05-01"
  resource_id            = join("/", slice(split("/", var.gateway_backend_subnet_id), 0, 9))
  response_export_values = ["location"]
}
