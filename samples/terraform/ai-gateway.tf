resource "azapi_resource" "gateway" {
  # AzAPI 2.13 does not yet include aigateways; keep legacy schema validation on.
  schema_validation_enabled = !local.gateway_is_2026
  type                      = "${local.gateway_type}@${local.gateway_api_version}"
  name                      = local.names.gateway
  parent_id                 = azapi_resource.resource_group["gateway"].id
  location                  = var.gateway_location
  tags                      = local.tags
  identity { type = "SystemAssigned" }
  # Selecting an object preserves number/null types and partially unknown subnet IDs.
  body = {
    "2026" = {
      sku = { name = "Consumption" }
      properties = var.gateway_backend_subnet_id == "" ? {} : {
        backend = { subnet = { id = var.gateway_backend_subnet_id } }
      }
    }
    legacy = {
      sku = { name = "AIGateway", capacity = 1 }
      properties = {
        publisherEmail      = var.publisher_email
        publisherName       = var.publisher_name
        publicNetworkAccess = var.gateway_public_network_access
        virtualNetworkType  = var.enable_private_networking ? "External" : "None"
        virtualNetworkConfiguration = var.enable_private_networking ? {
          subnetResourceId = local.private_gateway_subnet_id
        } : null
      }
    }
  }[var.gateway_contract]
  response_export_values = local.gateway_is_2026 ? ["properties.gatewayUrl", "properties.frontend.defaultHostname"] : ["properties.gatewayUrl"]
  create_headers         = local.gateway_is_2026 ? { "If-None-Match" = "*" } : {}
  replace_triggers_refs  = local.gateway_is_2026 ? ["properties.backend"] : []
  lifecycle {
    prevent_destroy = true
    precondition {
      condition = var.gateway_backend_subnet_id == "" || try(contains([
        for delegation in data.azapi_resource.gateway_backend_subnet[0].output.properties.delegations :
        lower(delegation.properties.serviceName)
      ], "microsoft.app/environments"), false)
      error_message = "The existing 2026 backend subnet must be delegated to Microsoft.App/environments. The workload does not modify platform-owned subnet configuration."
    }
    precondition {
      condition = var.gateway_backend_subnet_id == "" || try(
        lower(replace(data.azapi_resource.gateway_backend_vnet[0].output.location, " ", "")) == lower(replace(var.gateway_location, " ", "")),
        false
      )
      error_message = "The 2026 backend subnet VNet must be in gateway_location."
    }
  }
  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
  depends_on = [azapi_resource.private_dns_link, data.azapi_resource.existing_private_subnet]
}

resource "azapi_resource" "connector_gateway" {
  count = local.gateway_is_2026 ? 0 : 1
  # This preview type is not yet present in AzAPI's bundled schema.
  schema_validation_enabled = false
  type                      = "Microsoft.Web/connectorGateways@2026-05-01-preview"
  name                      = local.names.gateway
  parent_id                 = azapi_resource.resource_group["gateway"].id
  location                  = var.gateway_location
  body                      = { properties = {} }
  depends_on                = [azapi_resource.gateway]
}

moved {
  from = azapi_resource.connector_gateway
  to   = azapi_resource.connector_gateway[0]
}

locals {
  # The AIGateway service creates its default workspace; do not manage it twice.
  gateway_workspace_id      = "${azapi_resource.gateway.id}/workspaces/default"
  gateway_hostname          = try(trimspace(azapi_resource.gateway.output.properties.frontend.defaultHostname), "")
  gateway_url               = try(trimspace(azapi_resource.gateway.output.properties.gatewayUrl), "")
  gateway_frontend_endpoint = local.gateway_hostname == "" ? "" : "https://${local.gateway_hostname}"
  gateway_endpoint = local.gateway_is_2026 ? (
    local.gateway_frontend_endpoint != "" ? local.gateway_frontend_endpoint : local.gateway_url
    ) : (
    local.gateway_url != "" ? local.gateway_url : local.gateway_frontend_endpoint
  )
  gateway_aliases = var.model_aliases != null ? var.model_aliases : {
    for key, model in var.model_deployments : key => {
      alias_name  = key
      description = model.description
      backend_models = [{
        deployment = key
        priority   = null
        weight     = null
      }]
    }
  }
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
        kind           = "applicationInsights"
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

resource "azapi_resource" "foundry_provider" {
  # This preview type is not yet present in AzAPI's bundled schema.
  schema_validation_enabled = false
  type                      = "${local.gateway_type}/workspaces/modelProviders@${local.gateway_api_version}"
  name                      = "foundry"
  parent_id                 = local.gateway_workspace_id
  body = {
    properties = {
      kind        = "Foundry"
      displayName = "Foundry"
      description = "Managed-identity access to the dedicated Foundry model account."
      foundry = {
        endpoint    = "${trimsuffix(azapi_resource.models.output.properties.endpoint, "/")}/"
        resourceIds = [azapi_resource.models.id]
        authentication = {
          kind            = "ManagedIdentity"
          managedIdentity = { resource = "https://cognitiveservices.azure.com/" }
        }
      }
    }
  }
  depends_on = [azapi_resource.role_assignment["gateway-foundry-user"]]
}

resource "azapi_resource" "catalog_model" {
  # This preview type is not yet present in AzAPI's bundled schema.
  schema_validation_enabled = false
  for_each                  = var.model_deployments
  type                      = "${local.gateway_type}/workspaces/modelProviders/models@${local.gateway_api_version}"
  name                      = each.key
  parent_id                 = azapi_resource.foundry_provider.id
  body = {
    properties = {
      description        = each.value.description
      displayName        = each.value.model_name
      apiFormat          = each.value.api_format
      supportedEndpoints = each.value.endpoints
      deployment = {
        resourceId   = azapi_resource.model_deployment[each.key].id
        modelName    = each.key
        modelVersion = each.value.model_version
      }
      policies = concat([{
        type       = "tokenLimit"
        period     = "minute"
        count      = each.value.token_limit
        counterKey = ["identity"]
        }], each.value.cost_limit == null ? [] : [{
        id         = "monthly-caller-budget"
        type       = "costLimit"
        period     = "month"
        amount     = each.value.cost_limit
        counterKey = ["identity"]
        }], each.value.content_safety_severity == null ? [] : [{
        type             = "contentSafety"
        hateSeverity     = each.value.content_safety_severity
        selfHarmSeverity = each.value.content_safety_severity
        sexualSeverity   = each.value.content_safety_severity
        violenceSeverity = each.value.content_safety_severity
      }])
    }
  }
}

resource "azapi_resource" "model_alias" {
  # Runtime routing requires an alias in addition to the provider's catalog entry.
  schema_validation_enabled = false
  for_each                  = local.gateway_aliases
  type                      = "${local.gateway_type}/workspaces/aliases@${local.gateway_api_version}"
  name                      = each.key
  parent_id                 = local.gateway_workspace_id
  body = {
    properties = {
      aliasName   = each.value.alias_name
      description = each.value.description
      backendModels = [for backend in each.value.backend_models : merge({
        resourceId = try(azapi_resource.catalog_model[backend.deployment].id, null)
        },
        backend.priority == null ? {} : { priority = backend.priority },
        backend.weight == null ? {} : { weight = backend.weight }
      )]
    }
  }
  create_headers = local.gateway_is_2026 ? { "If-None-Match" = "*" } : {}
  delete_headers = local.gateway_is_2026 ? { "If-Match" = "*" } : {}
  # The 2026 alias update route is PATCH; AzAPI resource updates use PUT.
  # Replace changed aliases explicitly instead of pretending PUT implements PATCH.
  replace_triggers_refs = local.gateway_is_2026 ? ["properties"] : []
}

resource "azapi_resource" "runtime_api_key" {
  # This preview type is not yet present in AzAPI's bundled schema.
  schema_validation_enabled = false
  type                      = "${local.gateway_type}/apiKeys@${local.gateway_api_version}"
  name                      = "default"
  parent_id                 = azapi_resource.gateway.id
  body                      = { properties = { displayName = "All APIs subscription" } }
  response_export_values    = []
}
