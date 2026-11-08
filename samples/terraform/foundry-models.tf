resource "azapi_resource" "models" {
  type      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name      = local.names.models
  parent_id = local.resource_group_ids[local.resource_group_keys["models"]]
  location  = var.location
  tags      = local.tags
  identity { type = "SystemAssigned" }
  body = {
    kind = "AIServices"
    sku  = { name = "S0" }
    properties = {
      allowProjectManagement = local.gateway_is_2026
      customSubDomainName    = local.names.models
      disableLocalAuth       = true
      publicNetworkAccess    = local.backend_network_access.models
      networkAcls = {
        defaultAction       = local.backend_network_access.models == "Disabled" ? "Deny" : "Allow"
        virtualNetworkRules = []
        ipRules             = []
      }
    }
  }
  response_export_values = ["properties.endpoint"]
}

resource "azapi_resource" "model_deployment" {
  for_each  = var.model_deployments
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview"
  name      = each.key
  parent_id = azapi_resource.models.id
  # Cognitive Services permits only one deployment operation per account at a time.
  locks = [azapi_resource.models.id]
  body = {
    sku = {
      name     = each.value.sku_name
      capacity = each.value.capacity
    }
    properties = merge({
      model = {
        name    = each.value.model_name
        version = each.value.model_version
        format  = each.value.model_format
      }
      }, local.gateway_is_2026 ? {
      raiPolicyName = "Microsoft.DefaultV2"
    } : {})
  }
}
