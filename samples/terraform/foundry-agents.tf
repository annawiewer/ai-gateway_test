resource "azapi_resource" "agents" {
  type      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name      = local.names.agents
  parent_id = local.resource_group_ids[local.resource_group_keys["agents"]]
  location  = var.location
  tags      = local.tags
  identity { type = "SystemAssigned" }
  body = {
    kind = "AIServices"
    sku  = { name = "S0" }
    properties = {
      allowProjectManagement = true
      customSubDomainName    = local.names.agents
      disableLocalAuth       = true
      publicNetworkAccess    = local.backend_network_access.agents
      networkAcls = {
        defaultAction       = local.backend_network_access.agents == "Disabled" ? "Deny" : "Allow"
        virtualNetworkRules = []
        ipRules             = []
      }
    }
  }
}

resource "azapi_resource" "storage" {
  type      = "Microsoft.Storage/storageAccounts@2024-01-01"
  name      = local.names.storage
  parent_id = local.resource_group_ids[local.resource_group_keys["agents"]]
  location  = var.location
  tags      = local.tags
  body = {
    kind = "StorageV2"
    sku  = { name = "Standard_LRS" }
    properties = {
      minimumTlsVersion     = "TLS1_2"
      allowBlobPublicAccess = false
      allowSharedKeyAccess  = false
      publicNetworkAccess   = local.backend_network_access.storage
      networkAcls = merge({
        bypass              = var.api2026_private_lab_enabled ? "None" : "AzureServices"
        defaultAction       = var.standalone_backend_public_network_access == "Disabled" ? "Deny" : "Allow"
        virtualNetworkRules = []
        }, var.standalone_backend_public_network_access == "Disabled" ? {
        # AzAPI needs this path in the request body to overlay its live value.
        resourceAccessRules = []
      } : {})
    }
  }
  response_export_values = ["properties.primaryEndpoints.blob"]
  # Existing external-network deployments retain their reviewed policy overlay; fresh labs do not.
  ignore_body_changes = var.standalone_backend_public_network_access == "Disabled" && !var.api2026_private_lab_enabled ? [
    "properties.networkAcls.resourceAccessRules"
  ] : null
}

resource "azapi_resource" "registry" {
  type      = "Microsoft.ContainerRegistry/registries@2023-07-01"
  name      = local.names.registry
  parent_id = local.resource_group_ids[local.resource_group_keys["agents"]]
  location  = var.location
  tags      = local.tags
  identity { type = "SystemAssigned" }
  body = {
    sku = { name = "Premium" }
    properties = {
      adminUserEnabled    = false
      publicNetworkAccess = local.backend_network_access.registry
      zoneRedundancy      = "Disabled"
    }
  }
  response_export_values = ["properties.loginServer"]
}

resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name      = local.names.project
  parent_id = azapi_resource.agents.id
  location  = var.location
  tags      = local.tags
  identity { type = "SystemAssigned" }
  body = {
    properties = {
      displayName = var.project_display_name
      description = var.project_description
    }
  }
}

resource "azapi_resource" "storage_connection" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = local.names.storage
  parent_id = azapi_resource.project.id
  body = {
    properties = {
      category = "AzureStorageAccount"
      target   = azapi_resource.storage.output.properties.primaryEndpoints.blob
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azapi_resource.storage.id
        location   = var.location
      }
    }
  }
  depends_on = [azapi_resource.role_assignment["project-storage"]]
}

resource "azapi_resource" "registry_connection" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "${local.names.registry}-conn"
  parent_id = azapi_resource.project.id
  body = {
    properties = {
      category      = "ContainerRegistry"
      target        = azapi_resource.registry.output.properties.loginServer
      authType      = "ManagedIdentity"
      isSharedToAll = false
      credentials = {
        clientId   = azapi_resource.project.identity[0].principal_id
        resourceId = azapi_resource.registry.id
      }
      metadata = { ResourceId = azapi_resource.registry.id }
    }
  }
  depends_on = [azapi_resource.role_assignment["project-acr-pull"]]
}

moved {
  from = azapi_resource.insights_connection
  to   = azapi_resource.insights_connection[0]
}

resource "azapi_resource" "insights_connection" {
  count     = local.gateway_is_2026 ? 0 : 1
  type      = "Microsoft.CognitiveServices/accounts/connections@2025-06-01"
  name      = azapi_resource.insights["agents"].name
  parent_id = azapi_resource.agents.id
  body = {
    properties = {
      category      = "AppInsights"
      authType      = "ApiKey"
      isSharedToAll = true
      target        = azapi_resource.insights["agents"].id
      credentials   = { key = azapi_resource.insights["agents"].output.properties.ConnectionString }
      metadata = {
        # Use the component name for AppInsights ResourceId; target keeps its ARM ID.
        ApiType     = "Azure"
        ResourceId  = azapi_resource.insights["agents"].name
        displayName = azapi_resource.insights["agents"].name
      }
    }
  }
}

resource "azapi_resource" "project_insights_connection" {
  for_each  = local.gateway_is_2026 ? toset(["agents"]) : toset([])
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = azapi_resource.insights[each.key].name
  parent_id = azapi_resource.project.id
  body = {
    properties = {
      category      = "AppInsights"
      authType      = "ApiKey"
      isSharedToAll = false
      target        = azapi_resource.insights[each.key].id
      credentials   = { key = azapi_resource.insights[each.key].output.properties.ConnectionString }
      metadata = {
        ApiType    = "Azure"
        ResourceId = azapi_resource.insights[each.key].id
        location   = var.location
      }
    }
  }
}
