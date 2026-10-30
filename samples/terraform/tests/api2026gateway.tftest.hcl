mock_provider "azapi" {}

variables {
  subscription_id   = "00000000-0000-0000-0000-000000000001"
  environment_name  = "api2026gateway"
  location          = "eastus2"
  gateway_location  = "swedencentral"
  gateway_contract  = "2026"
  model_deployments = jsondecode(file("api2026gateway/bicep-profile.json")).model_deployments
  model_aliases     = jsondecode(file("api2026gateway/bicep-profile.json")).model_aliases
}

override_resource {
  target          = azapi_resource.resource_group["gateway"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/gateway"
  }
}

override_resource {
  target          = azapi_resource.resource_group["models"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/models"
  }
}

override_resource {
  target          = azapi_resource.resource_group["agents"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/agents"
  }
}

override_resource {
  target          = azapi_resource.gateway
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/gateway/providers/Microsoft.ApiManagement/aigateways/test"
    identity = {
      type         = "SystemAssigned"
      principal_id = "00000000-0000-0000-0000-000000000002"
      tenant_id    = "00000000-0000-0000-0000-000000000003"
      identity_ids = []
    }
    output = {
      properties = {
        frontend   = { defaultHostname = "new-gateway.example" }
        gatewayUrl = "https://fallback-gateway.example"
      }
    }
  }
}

override_resource {
  target          = azapi_resource.models
  override_during = plan
  values = {
    id     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/models/providers/Microsoft.CognitiveServices/accounts/models"
    output = { properties = { endpoint = "https://models.example/" } }
  }
}

override_resource {
  target          = azapi_resource.insights["gateway"]
  override_during = plan
  values = {
    id     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/gateway/providers/Microsoft.Insights/components/gateway"
    output = { properties = { ConnectionString = "test-connection-string" } }
  }
}

override_resource {
  target          = azapi_resource.insights["agents"]
  override_during = plan
  values = {
    id     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/agents/providers/Microsoft.Insights/components/agents"
    output = { properties = { ConnectionString = "test-agent-connection-string" } }
  }
}

override_resource {
  target          = azapi_resource.model_deployment["gpt-latest"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/models/providers/Microsoft.CognitiveServices/accounts/models/deployments/gpt-latest"
  }
}

override_resource {
  target          = azapi_resource.model_deployment["gpt-6-sol"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/models/providers/Microsoft.CognitiveServices/accounts/models/deployments/gpt-6-sol"
  }
}

override_resource {
  target          = azapi_resource.model_deployment["gpt-mini-latest"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/models/providers/Microsoft.CognitiveServices/accounts/models/deployments/gpt-mini-latest"
  }
}

override_resource {
  target          = azapi_resource.catalog_model["gpt-latest"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/gateway/providers/Microsoft.ApiManagement/aigateways/test/workspaces/default/modelProviders/foundry/models/gpt-latest"
  }
}

override_resource {
  target          = azapi_resource.catalog_model["gpt-6-sol"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/gateway/providers/Microsoft.ApiManagement/aigateways/test/workspaces/default/modelProviders/foundry/models/gpt-6-sol"
  }
}

override_resource {
  target          = azapi_resource.catalog_model["gpt-mini-latest"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/gateway/providers/Microsoft.ApiManagement/aigateways/test/workspaces/default/modelProviders/foundry/models/gpt-mini-latest"
  }
}

run "bicep_profile_routes_policies_and_placement" {
  command = plan

  assert {
    condition = (
      azapi_resource.gateway.type == "Microsoft.ApiManagement/aigateways@2026-09-01-preview" &&
      azapi_resource.gateway.body.sku.name == "Consumption" &&
      !can(azapi_resource.gateway.body.sku.capacity) &&
      length(keys(azapi_resource.gateway.body.properties)) == 0 &&
      length(azapi_resource.connector_gateway) == 0 &&
      length(azapi_resource.private_endpoint) == 0 &&
      output.gateway_endpoint == "https://new-gateway.example" &&
      output.gateway_api_versions.api_keys == "2026-09-01-preview" &&
      output.gateway_api_versions.telemetry == "2025-09-01-preview" &&
      local.resource_token != substr(sha256("${var.subscription_id}:${var.environment_name}:${var.location}"), 0, 12)
    )
    error_message = "The isolated 2026 root must not inherit legacy SKU/properties/connector/private endpoints or names; expose the actual host and explicit mixed API versions."
  }

  assert {
    condition = (
      length(azapi_resource.resource_group) == 3 &&
      length(distinct(values(output.resource_groups))) == 3 &&
      azapi_resource.gateway.parent_id == azapi_resource.resource_group["gateway"].id &&
      azapi_resource.models.parent_id == azapi_resource.resource_group["models"].id &&
      alltrue([for parent in [
        azapi_resource.agents.parent_id,
        azapi_resource.storage.parent_id,
        azapi_resource.registry.parent_id,
        azapi_resource.logs["agents"].parent_id,
        azapi_resource.insights["agents"].parent_id
      ] : parent == azapi_resource.resource_group["agents"].id]) &&
      azapi_resource.logs["gateway"].parent_id == azapi_resource.resource_group["gateway"].id &&
      azapi_resource.insights["gateway"].parent_id == azapi_resource.resource_group["gateway"].id
    )
    error_message = "Bicep parity requires actual three-group placement, not three empty groups with everything in gateway."
  }

  assert {
    condition = length(azapi_resource.model_deployment) == 3 && alltrue([
      for key, model in var.model_deployments :
      azapi_resource.model_deployment[key].parent_id == azapi_resource.models.id &&
      azapi_resource.model_deployment[key].body.properties.model.name == model.model_name &&
      azapi_resource.model_deployment[key].body.properties.model.version == model.model_version &&
      azapi_resource.model_deployment[key].body.sku.name == model.sku_name &&
      azapi_resource.model_deployment[key].body.sku.capacity == model.capacity &&
      azapi_resource.catalog_model[key].body.properties.deployment.resourceId == azapi_resource.model_deployment[key].id &&
      azapi_resource.catalog_model[key].body.properties.deployment.modelName == key &&
      azapi_resource.catalog_model[key].body.properties.displayName == model.model_name &&
      length(azapi_resource.catalog_model[key].body.properties.policies) == 3 &&
      azapi_resource.catalog_model[key].body.properties.policies[0].count == model.token_limit &&
      jsonencode(azapi_resource.catalog_model[key].body.properties.policies[0].counterKey) == jsonencode(["identity"]) &&
      azapi_resource.catalog_model[key].body.properties.policies[1].amount == model.cost_limit &&
      azapi_resource.catalog_model[key].body.properties.policies[1].period == "month" &&
      jsonencode(azapi_resource.catalog_model[key].body.properties.policies[1].counterKey) == jsonencode(["identity"]) &&
      alltrue([for category in ["hateSeverity", "selfHarmSeverity", "sexualSeverity", "violenceSeverity"] :
        azapi_resource.catalog_model[key].body.properties.policies[2][category] == model.content_safety_severity
      ])
    ])
    error_message = "The Bicep profile must drive real Foundry deployments, matching catalog routes and identity-keyed governance policies."
  }

  assert {
    condition = (
      length(azapi_resource.model_alias) == 2 &&
      alltrue(flatten([for key, alias in var.model_aliases : [
        for index, backend in alias.backend_models :
        azapi_resource.model_alias[key].body.properties.aliasName == alias.alias_name &&
        azapi_resource.model_alias[key].body.properties.backendModels[index].resourceId == azapi_resource.catalog_model[backend.deployment].id &&
        azapi_resource.model_alias[key].body.properties.backendModels[index].priority == backend.priority &&
        azapi_resource.model_alias[key].body.properties.backendModels[index].weight == backend.weight
      ]])) &&
      output.model_alias_configuration["primary-router"].alias_name == "gpt-latest" &&
      length(output.model_alias_configuration["primary-router"].backend_models) == 3 &&
      output.model_alias_configuration["mini-router"].alias_name == "gpt-mini-latest"
    )
    error_message = "Three deployments must produce two callable aliases, preserving prioritized/weighted backends rather than one alias per deployment."
  }

  assert {
    condition = (
      azapi_resource.telemetry_exporter.type == "Microsoft.ApiManagement/aigateways/workspaces/telemetryExporters@2025-09-01-preview" &&
      azapi_resource.telemetry_exporter.body.properties.kind == "applicationInsights" &&
      !azapi_resource.telemetry_exporter.body.properties.payloadCapture &&
      azapi_resource.telemetry_exporter.body.properties.applicationInsights.connectionString == "test-connection-string" &&
      !can(azapi_resource.telemetry_exporter.body.properties.openTelemetry) &&
      !can(azapi_resource.insights["gateway"].body.properties.AzureMonitorWorkspaceIngestionMode) &&
      !contains(keys(azapi_resource.role_assignment), "gateway-monitoring-publisher") &&
      output.gateway_monitoring.kind == "applicationInsights" &&
      length(azapi_resource.role_assignment) == 6 &&
      azapi_resource.role_assignment["gateway-foundry-user"].parent_id == azapi_resource.models.id &&
      azapi_resource.role_assignment["gateway-foundry-user"].body.properties.principalId == azapi_resource.gateway.identity[0].principal_id &&
      azapi_resource.foundry_provider.body.properties.foundry.authentication.kind == "ManagedIdentity" &&
      !azapi_resource.models.body.properties.allowProjectManagement &&
      azapi_resource.agents.body.properties.allowProjectManagement &&
      azapi_resource.models.body.properties.disableLocalAuth &&
      azapi_resource.agents.body.properties.disableLocalAuth &&
      !azapi_resource.storage.body.properties.allowSharedKeyAccess &&
      !azapi_resource.registry.body.properties.adminUserEnabled &&
      azapi_resource.registry_connection.body.properties.isSharedToAll &&
      !azapi_resource.insights_connection.body.properties.isSharedToAll
    )
    error_message = "Match Bicep monitoring, identity and connection-sharing boundaries without legacy OTLP grants, automatic developer roles, shared keys or registry admin access."
  }

  assert {
    condition = (
      azapi_resource.insights_connection.body.properties.metadata.ResourceId == azapi_resource.insights["agents"].name &&
      azapi_resource.insights_connection.body.properties.target == azapi_resource.insights["agents"].id &&
      azapi_resource.insights_connection.body.properties.target != azapi_resource.insights_connection.body.properties.metadata.ResourceId &&
      azapi_resource.insights_connection.body.properties.credentials.key == azapi_resource.insights["agents"].output.properties.ConnectionString
    )
    error_message = "The 2026 entry must retain the AppInsights metadata-name workaround while keeping the full ARM ID target and connection-string credentials."
  }
}

run "nullable_frontend_falls_back_to_returned_gateway_url" {
  command = plan
  override_resource {
    target          = azapi_resource.gateway
    override_during = plan
    values = {
      id     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/gateway/providers/Microsoft.ApiManagement/aigateways/test"
      output = { properties = { frontend = { defaultHostname = null }, gatewayUrl = "https://fallback-gateway.example" } }
    }
  }
  assert {
    condition     = output.gateway_endpoint == "https://fallback-gateway.example"
    error_message = "A null frontend hostname must use the returned gatewayUrl, never an invented legacy hostname or an empty result."
  }
}

run "alias_metadata_intersects_backend_protocols" {
  command = plan
  variables {
    model_deployments = merge(jsondecode(file("api2026gateway/bicep-profile.json")).model_deployments, {
      gpt-6-sol = merge(jsondecode(file("api2026gateway/bicep-profile.json")).model_deployments["gpt-6-sol"], {
        endpoints = ["/openai/v1/responses"]
      })
    })
  }
  assert {
    condition = (
      jsonencode(output.model_alias_configuration["primary-router"].endpoints) == jsonencode(["/openai/v1/responses"]) &&
      contains(output.model_alias_configuration["mini-router"].endpoints, "/openai/v1/chat/completions")
    )
    error_message = "A routed alias must advertise only common backend endpoints so chat probes cannot silently exercise an incompatible failover target."
  }
}

run "reject_missing_application_insights_destination" {
  command = plan
  override_resource {
    target          = azapi_resource.insights["gateway"]
    override_during = plan
    values = {
      id     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/gateway/providers/Microsoft.Insights/components/gateway"
      output = { properties = {} }
    }
  }
  expect_failures = [azapi_resource.telemetry_exporter]
}

run "existing_backend_subnet_is_outbound_only" {
  command = plan
  variables {
    gateway_backend_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/platform/providers/Microsoft.Network/virtualNetworks/shared/subnets/backend"
  }
  override_data {
    target = data.azapi_resource.gateway_backend_subnet[0]
    values = { output = { properties = { delegations = [{ properties = { serviceName = "Microsoft.App/environments" } }] } } }
  }
  override_data {
    target = data.azapi_resource.gateway_backend_vnet[0]
    values = { output = { location = "Sweden Central" } }
  }
  assert {
    condition = (
      azapi_resource.gateway.body.properties.backend.subnet.id == var.gateway_backend_subnet_id &&
      jsonencode(keys(azapi_resource.gateway.body.properties)) == jsonencode(["backend"]) &&
      length(azapi_resource.private_endpoint) == 0 &&
      length(azapi_resource.private_dns_link) == 0 &&
      !can(azapi_resource.gateway.body.properties.publicNetworkAccess) &&
      jsonencode(azapi_resource.gateway.replace_triggers_refs) == jsonencode(["properties.backend"]) &&
      data.azapi_resource.gateway_backend_vnet[0].resource_id == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/platform/providers/Microsoft.Network/virtualNetworks/shared"
    )
    error_message = "Only the documented creation-time backend subnet may be sent. Do not mutate platform DNS or infer private ingress from outbound integration."
  }
}

run "reject_legacy_subnet_delegation" {
  command = plan
  variables {
    gateway_backend_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/platform/providers/Microsoft.Network/virtualNetworks/shared/subnets/backend"
  }
  override_data {
    target = data.azapi_resource.gateway_backend_subnet[0]
    values = { output = { properties = { delegations = [{ properties = { serviceName = "Microsoft.Web/serverFarms" } }] } } }
  }
  override_data {
    target = data.azapi_resource.gateway_backend_vnet[0]
    values = { output = { location = "swedencentral" } }
  }
  expect_failures = [azapi_resource.gateway]
}

run "reject_backend_subnet_in_wrong_region" {
  command = plan
  variables {
    gateway_backend_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/platform/providers/Microsoft.Network/virtualNetworks/shared/subnets/backend"
  }
  override_data {
    target = data.azapi_resource.gateway_backend_subnet[0]
    values = { output = { properties = { delegations = [{ properties = { serviceName = "Microsoft.App/environments" } }] } } }
  }
  override_data {
    target = data.azapi_resource.gateway_backend_vnet[0]
    values = { output = { location = "eastus2" } }
  }
  expect_failures = [azapi_resource.gateway]
}

run "reject_unverified_private_ingress_profile" {
  command = plan
  variables {
    enable_private_networking = true
  }
  expect_failures = [var.enable_private_networking]
}

run "reject_unknown_alias_deployment" {
  command = plan
  variables {
    model_aliases = {
      router = { alias_name = "client-name", backend_models = [{ deployment = "missing" }] }
    }
  }
  expect_failures = [var.model_aliases]
}

run "reject_repeated_route_target" {
  command = plan
  variables {
    model_aliases = {
      router = { alias_name = "client-name", backend_models = [
        { deployment = "gpt-latest", priority = 0 },
        { deployment = "gpt-latest", priority = 1 }
      ] }
    }
  }
  expect_failures = [var.model_aliases]
}

run "reject_invalid_routing_numbers" {
  command = plan
  variables {
    model_aliases = {
      router = { alias_name = "client-name", backend_models = [{ deployment = "gpt-latest", priority = 0.5, weight = 0 }] }
    }
  }
  expect_failures = [var.model_aliases]
}

run "reject_incompatible_backend_protocols" {
  command = plan
  variables {
    model_deployments = merge(jsondecode(file("api2026gateway/bicep-profile.json")).model_deployments, {
      gpt-6-sol = merge(jsondecode(file("api2026gateway/bicep-profile.json")).model_deployments["gpt-6-sol"], {
        api_format = "Other"
      })
    })
  }
  expect_failures = [var.model_aliases]
}

run "reject_invalid_governance_settings" {
  command = plan
  variables {
    model_deployments = merge(jsondecode(file("api2026gateway/bicep-profile.json")).model_deployments, {
      gpt-6-sol = merge(jsondecode(file("api2026gateway/bicep-profile.json")).model_deployments["gpt-6-sol"], {
        cost_limit              = 0
        content_safety_severity = "Unknown"
      })
    })
  }
  expect_failures = [var.model_deployments]
}
