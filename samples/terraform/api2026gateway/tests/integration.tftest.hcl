# The real wrapper and child module execute against a mocked provider.
# Test-Api2026Wrapper.ps1 additionally inspects nested plan resources, which are
# intentionally not added to the production module's output interface.
mock_provider "azapi" {}

variables {
  subscription_id  = "00000000-0000-0000-0000-000000000001"
  environment_name = "wrapper-fixture"
  location         = "swedencentral"
  gateway_location = "swedencentral"
}

override_resource {
  target          = module.gateway.azapi_resource.gateway
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/gateway/providers/Microsoft.ApiManagement/aigateways/fixture"
    identity = {
      type         = "SystemAssigned"
      principal_id = "00000000-0000-0000-0000-000000000002"
      tenant_id    = "00000000-0000-0000-0000-000000000003"
      identity_ids = []
    }
    output = { properties = { frontend = { defaultHostname = "fixture.example" } } }
  }
}

override_resource {
  target          = module.gateway.azapi_resource.models
  override_during = plan
  values = {
    id     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/models/providers/Microsoft.CognitiveServices/accounts/models"
    output = { properties = { endpoint = "https://models.example/" } }
  }
}

override_resource {
  target          = module.gateway.azapi_resource.project
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/agents/providers/Microsoft.CognitiveServices/accounts/agents/projects/project"
    identity = {
      type         = "SystemAssigned"
      principal_id = "00000000-0000-0000-0000-000000000006"
      tenant_id    = "00000000-0000-0000-0000-000000000003"
      identity_ids = []
    }
  }
}

override_resource {
  target          = module.gateway.azapi_resource.insights["gateway"]
  override_during = plan
  values = {
    id     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/gateway/providers/Microsoft.Insights/components/gateway"
    output = { properties = { ConnectionString = "synthetic-gateway-connection" } }
  }
}

override_resource {
  target          = module.gateway.azapi_resource.insights["agents"]
  override_during = plan
  values = {
    id     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/agents/providers/Microsoft.Insights/components/agents"
    output = { properties = { ConnectionString = "synthetic-agents-connection" } }
  }
}

run "default_profile_reaches_child" {
  command = plan

  assert {
    condition = (
      output.gateway_contract.name == "2026" &&
      output.gateway_contract.resource_type == "Microsoft.ApiManagement/aigateways" &&
      alltrue([for key in ["gateway", "catalog", "aliases", "api_keys"] : output.gateway_api_versions[key] == "2026-09-01-preview"]) &&
      output.gateway_api_versions.telemetry == "2025-09-01-preview" &&
      output.gateway_endpoint == "https://fixture.example" &&
      output.gateway_monitoring.kind == "applicationInsights" &&
      alltrue([for key in ["models", "agents", "storage", "registry"] : output.backend_public_network_access[key] == "Enabled"]) &&
      output.backend_public_network_access.monitoring_ingestion == "Unspecified" &&
      output.backend_public_network_access.monitoring_query == "Unspecified" &&
      length(distinct(values(output.resource_groups))) == 3 &&
      jsonencode(keys(output.model_deployment_ids)) == jsonencode(keys(local.default_profile.model_deployments)) &&
      jsonencode(keys(output.model_alias_configuration)) == jsonencode(keys(local.default_profile.model_aliases)) &&
      output.model_alias_configuration["primary-router"].alias_name == "gpt-latest" &&
      length(output.model_alias_configuration["primary-router"].backend_models) == 3 &&
      output.model_alias_configuration["mini-router"].alias_name == "gpt-mini-latest"
    )
    error_message = "The wrapper must exercise the real child module and forward its default profile, contract and outputs."
  }
}

run "explicit_inputs_reach_child" {
  command = plan
  variables {
    standalone_backend_public_network_access = "Disabled"
    gateway_backend_subnet_id                = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/platform/providers/Microsoft.Network/virtualNetworks/shared/subnets/backend"
    gateway_access_principals = {
      fixture = { principal_id = "00000000-0000-0000-0000-000000000004", principal_type = "ServicePrincipal" }
    }
    developer_principal_id     = "00000000-0000-0000-0000-000000000005"
    developer_principal_type   = "Group"
    model_allowed_client_cidrs = ["203.0.113.42/32", "2001:db8:1234::/48"]
    model_deployments = {
      custom-model = {
        model_name    = "gpt-5.4-mini"
        model_version = "2026-03-17"
        capacity      = 7
        token_limit   = 700
        cost_limit    = 3
        request_limit = 17
        endpoints     = ["/openai/v1/chat/completions"]
      }
    }
    model_aliases = {
      custom-route = {
        alias_name = "custom-callable"
        backend_models = [{
          deployment = "custom-model"
          priority   = 2
          weight     = 75
        }]
      }
    }
    tags = { fixture = "forwarded" }
  }

  override_data {
    target = module.gateway.data.azapi_resource.gateway_backend_subnet[0]
    values = { output = { properties = { delegations = [{ properties = { serviceName = "Microsoft.App/environments" } }] } } }
  }
  override_data {
    target = module.gateway.data.azapi_resource.gateway_backend_vnet[0]
    values = { output = { location = "Sweden Central" } }
  }

  assert {
    condition = (
      output.gateway_contract.backend_subnet_id == var.gateway_backend_subnet_id &&
      alltrue([for access in values(output.backend_public_network_access) : access == "Disabled"]) &&
      jsonencode(keys(output.model_deployment_ids)) == jsonencode(["custom-model"]) &&
      jsonencode(keys(output.model_alias_configuration)) == jsonencode(["custom-route"]) &&
      output.model_alias_configuration["custom-route"].alias_name == "custom-callable" &&
      output.model_alias_configuration["custom-route"].backend_models[0].deployment == "custom-model" &&
      output.model_alias_configuration["custom-route"].backend_models[0].priority == 2 &&
      output.model_alias_configuration["custom-route"].backend_models[0].weight == 75 &&
      jsonencode(output.model_api_configuration["custom-model"].endpoints) == jsonencode(["/openai/v1/chat/completions"])
    )
    error_message = "Explicit model/alias maps replace the complete default maps; subnet and route metadata must reach the real child."
  }
}
