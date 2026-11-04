resource "azapi_resource" "logs" {
  for_each  = toset(["gateway", "agents"])
  type      = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  name      = "${local.names[each.key]}-logs"
  parent_id = azapi_resource.resource_group[local.resource_group_keys[each.key]].id
  location  = var.location
  tags      = local.tags
  body = {
    properties = merge({
      retentionInDays = 30
      features        = { enableLogAccessUsingOnlyResourcePermissions = true }
      sku             = { name = "PerGB2018" }
    }, local.backend_monitoring_access)
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
    }, local.backend_monitoring_access, !local.gateway_is_2026 && each.key == "gateway" ? { AzureMonitorWorkspaceIngestionMode = "Enabled" } : {})
  }
  response_export_values = !local.gateway_is_2026 && each.key == "gateway" ? [
    "properties.OTLPMetricsEndpoint",
    "properties.OTLPLogsEndpoint",
    "properties.OTLPTracesEndpoint",
    "properties.DataCollectionRuleResourceId",
    "properties.DataCollectionRuleId"
  ] : ["properties.ConnectionString"]
}

locals {
  gateway_monitoring = {
    dcr_id = try(coalesce(
      try(azapi_resource.insights["gateway"].output.properties.DataCollectionRuleResourceId, null),
      try(azapi_resource.insights["gateway"].output.properties.DataCollectionRuleId, null)
    ), "")
    metrics_endpoint = try(coalesce(azapi_resource.insights["gateway"].output.properties.OTLPMetricsEndpoint), "")
    logs_endpoint    = try(coalesce(azapi_resource.insights["gateway"].output.properties.OTLPLogsEndpoint), "")
    traces_endpoint  = try(coalesce(azapi_resource.insights["gateway"].output.properties.OTLPTracesEndpoint), "")
  }
}

resource "azapi_resource" "telemetry_exporter" {
  # This preview type is not yet present in AzAPI's bundled schema.
  schema_validation_enabled = false
  type                      = "${local.gateway_type}/workspaces/telemetryExporters@${local.gateway_telemetry_api_version}"
  name                      = "appinsights"
  parent_id                 = local.gateway_workspace_id
  body = {
    properties = {
      "2026" = {
        kind           = "ApplicationInsights"
        payloadCapture = false
        applicationInsights = {
          connectionString = try(azapi_resource.insights["gateway"].output.properties.ConnectionString, null)
          resourceId       = azapi_resource.insights["gateway"].id
        }
      }
      legacy = {
        kind           = "OpenTelemetry"
        payloadCapture = false
        applicationInsights = {
          resourceId = azapi_resource.insights["gateway"].id
        }
        openTelemetry = {
          metricsEndpoint = local.gateway_monitoring.metrics_endpoint
          logsEndpoint    = local.gateway_monitoring.logs_endpoint
          tracesEndpoint  = local.gateway_monitoring.traces_endpoint
          credentials = {
            managedIdentity = { resource = "https://monitor.azure.com" }
          }
        }
      }
    }[var.gateway_contract]
  }
  lifecycle {
    precondition {
      condition = !local.gateway_is_2026 || try(
        length(trimspace(azapi_resource.insights["gateway"].output.properties.ConnectionString)) > 0,
        false
      )
      error_message = "The 2026 Application Insights exporter requires the returned gateway Insights ConnectionString. Do not silently deploy an incomplete exporter."
    }
    precondition {
      condition = local.gateway_is_2026 || alltrue([
        for endpoint in [
          local.gateway_monitoring.metrics_endpoint,
          local.gateway_monitoring.logs_endpoint,
          local.gateway_monitoring.traces_endpoint
        ] : can(regex("^https://[^/?#]+/[^?#]+$", endpoint))
      ])
      error_message = "Gateway OTLP endpoints are incomplete. Enable gateway Insights first, run scripts/Get-GatewayMonitoring.ps1, then create a fresh plan; see 01-04-deployment.md#monitoring-setup."
    }
  }
  depends_on = [azapi_resource.role_assignment]
}
