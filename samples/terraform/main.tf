locals {
  gateway_is_2026     = var.gateway_contract == "2026"
  gateway_type        = local.gateway_is_2026 ? "Microsoft.ApiManagement/aigateways" : "Microsoft.ApiManagement/service"
  gateway_api_version = local.gateway_is_2026 ? "2026-09-01-preview" : "2025-09-01-preview"
  # The published Bicep exporter contract is 2025; no 2026 exporter schema is established.
  gateway_telemetry_api_version = "2025-09-01-preview"
  resource_group_keys           = { for key in ["gateway", "models", "agents"] : key => local.gateway_is_2026 ? key : "gateway" }
  subscription_scope            = "/subscriptions/${var.subscription_id}"
  resource_token                = substr(sha256("${var.subscription_id}:${var.environment_name}:${var.location}${local.gateway_is_2026 ? ":api2026gateway" : ""}"), 0, 12)
  backend_token                 = var.backend_revision == "" ? local.resource_token : substr(sha256("${local.resource_token}:${var.backend_revision}"), 0, 12)
  tags                          = merge(var.tags, { environment = var.environment_name })
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
  # Keep the existing gateway address and name so consolidation cannot replace it.
  for_each  = toset(local.gateway_is_2026 || var.retain_legacy_resource_groups ? ["gateway", "models", "agents"] : ["gateway"])
  type      = "Microsoft.Resources/resourceGroups@2021-04-01"
  name      = "rg-${var.environment_name}-${local.resource_token}-${each.key}"
  parent_id = local.subscription_scope
  location  = var.location
  tags      = local.tags
  body      = { properties = {} }
}

resource "azapi_resource" "logs" {
  for_each  = toset(["gateway", "agents"])
  type      = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  name      = "${local.names[each.key]}-logs"
  parent_id = azapi_resource.resource_group[local.resource_group_keys[each.key]].id
  location  = var.location
  tags      = local.tags
  body = {
    properties = {
      retentionInDays = 30
      features        = { enableLogAccessUsingOnlyResourcePermissions = true }
      sku             = { name = "PerGB2018" }
    }
  }
}

resource "azapi_resource" "insights" {
  # OTLP enablement is supported by the service but absent from the bundled schema.
  schema_validation_enabled = local.gateway_is_2026 || each.key != "gateway"
  for_each                  = toset(["gateway", "agents"])
  type                      = "Microsoft.Insights/components@2020-02-02"
  name                      = "${local.names[each.key]}-insights"
  parent_id                 = azapi_resource.resource_group[local.resource_group_keys[each.key]].id
  location                  = var.location
  tags                      = local.tags
  body = {
    kind = "web"
    properties = merge({
      Application_Type    = "web"
      IngestionMode       = "LogAnalytics"
      WorkspaceResourceId = azapi_resource.logs[each.key].id
    }, !local.gateway_is_2026 && each.key == "gateway" ? { AzureMonitorWorkspaceIngestionMode = "Enabled" } : {})
  }
  response_export_values = !local.gateway_is_2026 && each.key == "gateway" ? [
    "properties.OTLPMetricsEndpoint",
    "properties.OTLPLogsEndpoint",
    "properties.OTLPTracesEndpoint",
    "properties.DataCollectionRuleResourceId",
    "properties.DataCollectionRuleId"
  ] : ["properties.ConnectionString"]
}
