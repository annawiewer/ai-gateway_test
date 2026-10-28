mock_provider "azapi" {
  mock_data "azapi_resource" {
    defaults = {
      output = {
        location         = "swedencentral"
        address_prefixes = ["10.50.1.0/24"]
        delegations      = []
      }
    }
  }
}

override_resource {
  target          = azapi_resource.insights["gateway"]
  override_during = plan
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/shared-gateway/providers/Microsoft.Insights/components/gateway"
    output = {
      properties = {
        DataCollectionRuleResourceId = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/managed-monitoring/providers/Microsoft.Insights/dataCollectionRules/gateway"
        OTLPMetricsEndpoint          = "https://test.metrics.ingest.monitor.azure.com/dataCollectionRules/dcr-test/streams/Microsoft-OTLP-Metrics/otlp/v1/metrics"
        OTLPLogsEndpoint             = "https://test.ingest.monitor.azure.com/dataCollectionRules/dcr-test/streams/Microsoft-OTLP-Logs/otlp/v1/logs"
        OTLPTracesEndpoint           = "https://test.ingest.monitor.azure.com/dataCollectionRules/dcr-test/streams/Microsoft-OTLP-Traces/otlp/v1/traces"
      }
    }
  }
}

override_data {
  target = data.azapi_resource.existing_private_subnet["gateway"]
  values = {
    output = {
      address_prefixes          = ["10.50.0.0/27"]
      delegations               = ["Microsoft.Web/serverFarms"]
      network_security_group_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/network-gateway/providers/Microsoft.Network/networkSecurityGroups/gateway"
    }
  }
}

override_data {
  target = data.azapi_resource.existing_private_subnet["endpoint_models"]
  values = {
    output = { address_prefixes = ["10.60.1.0/24"], delegations = [] }
  }
}

override_data {
  target = data.azapi_resource.existing_private_vnet["endpoint_models"]
  values = {
    output = { location = "germanywestcentral" }
  }
}

override_data {
  target = data.azapi_resource.existing_private_subnet["agents"]
  values = {
    output = { address_prefixes = ["10.70.0.0/24"], delegations = ["Microsoft.App/environments"] }
  }
}

override_data {
  target = data.azapi_resource.existing_private_vnet["agents"]
  values = {
    output = { location = "germanywestcentral" }
  }
}

override_data {
  target = data.azapi_resource.existing_private_subnet["endpoint_agents"]
  values = {
    output = { address_prefixes = ["10.70.1.0/24"], delegations = [] }
  }
}

override_data {
  target = data.azapi_resource.existing_private_subnet["endpoint_registry"]
  values = {
    output = { address_prefixes = ["10.70.2.0/24"], delegations = [] }
  }
}

override_data {
  target = data.azapi_resource.existing_private_subnet["endpoint_storage"]
  values = {
    output = { address_prefixes = ["10.80.1.0/24"], delegations = [] }
  }
}

override_data {
  target = data.azapi_resource.existing_private_subnet["client"]
  values = {
    output = { address_prefixes = ["10.90.0.0/24"], delegations = [] }
  }
}

override_data {
  target = data.azapi_resource.existing_private_vnet["client"]
  values = {
    output = { location = "germanywestcentral" }
  }
}

variables {
  subscription_id               = "00000000-0000-0000-0000-000000000001"
  location                      = "swedencentral"
  gateway_location              = "swedencentral"
  publisher_email               = "test@example.com"
  enable_private_networking     = true
  private_network_mode          = "existing"
  gateway_public_network_access = "Disabled"
  models_public_network_access  = "Disabled"
  existing_private_network = {
    gateway_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/network-gateway/providers/Microsoft.Network/virtualNetworks/gateway/subnets/integration"
    endpoint_subnet_ids = {
      gateway = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/network-gateway/providers/Microsoft.Network/virtualNetworks/gateway/subnets/gateway-private-links"
      models  = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/network-models/providers/Microsoft.Network/virtualNetworks/models/subnets/model-private-links"
    }
    private_dns_zone_ids = {
      gateway           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/central-dns/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net"
      cognitiveservices = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/central-dns/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com"
      openai            = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/central-dns/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com"
      services          = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/central-dns/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
    }
  }
  model_deployments = {
    test-model = {
      model_name    = "test-model-name"
      model_version = "test-version"
      capacity      = 1
      token_limit   = 100
    }
  }
}

run "reuse_central_dns_and_distinct_service_subnets" {
  command = plan
  variables {
    private_network_mode              = jsondecode(file("profiles/network-existing.tfvars.json")).private_network_mode
    private_dns_zone_group_management = jsondecode(file("profiles/network-existing.tfvars.json")).private_dns_zone_group_management
    existing_private_network = jsondecode(replace(
      file("profiles/network-existing.tfvars.json"),
      "00000000-0000-0000-0000-000000000000",
      var.subscription_id
    )).existing_private_network
  }

  assert {
    condition = (
      length(azapi_resource.private_vnet) == 0 &&
      length(azapi_resource.private_subnet) == 0 &&
      length(azapi_resource.private_nsg) == 0 &&
      length(azapi_resource.private_dns_zone) == 0 &&
      length(azapi_resource.private_dns_link) == 0 &&
      length(azapi_resource.private_test_vm) == 0
    )
    error_message = "Reuse must not create or adopt platform network/DNS foundation resources or an unsolicited test VM."
  }
  assert {
    condition = (
      azapi_resource.gateway.body.properties.virtualNetworkConfiguration.subnetResourceId == var.existing_private_network.gateway_subnet_id &&
      azapi_resource.private_endpoint["gateway"].body.properties.subnet.id == var.existing_private_network.endpoint_subnet_ids.gateway &&
      azapi_resource.private_endpoint["models"].body.properties.subnet.id == var.existing_private_network.endpoint_subnet_ids.models &&
      azapi_resource.private_endpoint["gateway"].location == "swedencentral" &&
      azapi_resource.private_endpoint["models"].location == "germanywestcentral" &&
      azapi_resource.gateway.body.properties.publicNetworkAccess == "Disabled" &&
      azapi_resource.models.body.properties.publicNetworkAccess == "Disabled"
    )
    error_message = "Private connections must use the exact supplied subnets and their actual regions without changing public access."
  }
  assert {
    condition = (
      azapi_resource.private_dns_zone_group["gateway"].body.properties.privateDnsZoneConfigs[0].properties.privateDnsZoneId == var.existing_private_network.private_dns_zone_ids.gateway &&
      alltrue([for config in azapi_resource.private_dns_zone_group["models"].body.properties.privateDnsZoneConfigs :
        config.properties.privateDnsZoneId == var.existing_private_network.private_dns_zone_ids[config.name]
      ]) &&
      jsonencode(output.private_network_configuration.endpoint_subnet_prefixes.models) == jsonencode(["10.60.1.0/24"]) &&
      output.private_network_configuration.gateway_subnet_id == var.existing_private_network.gateway_subnet_id &&
      output.private_probe_configuration == null
    )
    error_message = "DNS associations must reference central zones and outputs must describe real external subnet metadata."
  }
}

run "reuse_optional_agents_storage_and_client" {
  command = plan
  variables {
    location                           = "germanywestcentral"
    enable_private_hosted_agent        = true
    enable_storage_private_endpoint    = true
    storage_public_network_access      = "Disabled"
    enable_private_test_client         = true
    private_test_client_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleOnlyNotForDeployment"
    private_network_address_prefix     = "unused-in-existing-mode"
    existing_private_network = merge(var.existing_private_network, {
      agent_subnet_id  = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/network-agents/providers/Microsoft.Network/virtualNetworks/agents/subnets/runtime"
      client_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/network-client/providers/Microsoft.Network/virtualNetworks/client/subnets/probe"
      endpoint_subnet_ids = merge(var.existing_private_network.endpoint_subnet_ids, {
        storage  = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/network-storage/providers/Microsoft.Network/virtualNetworks/storage/subnets/blob-pe"
        agents   = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/network-agents/providers/Microsoft.Network/virtualNetworks/agents/subnets/account-pe"
        registry = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/network-agents/providers/Microsoft.Network/virtualNetworks/agents/subnets/registry-pe"
      })
      private_dns_zone_ids = merge(var.existing_private_network.private_dns_zone_ids, {
        storage  = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/central-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
        registry = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/central-dns/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
      })
    })
  }
  assert {
    condition = (
      length(azapi_resource.private_subnet) == 0 &&
      length(azapi_resource.private_dns_zone) == 0 &&
      length(azapi_resource.private_endpoint) == 3 &&
      length(azapi_resource.private_agent_endpoint) == 2 &&
      azapi_resource.private_agents[0].body.properties.networkInjections[0].subnetArmId == var.existing_private_network.agent_subnet_id &&
      azapi_resource.private_agent_endpoint["registry"].body.properties.subnet.id == var.existing_private_network.endpoint_subnet_ids.registry &&
      azapi_resource.private_agent_dns_zone_group["registry"].body.properties.privateDnsZoneConfigs[0].properties.privateDnsZoneId == var.existing_private_network.private_dns_zone_ids.registry &&
      azapi_resource.private_test_nic[0].body.properties.ipConfigurations[0].properties.subnet.id == var.existing_private_network.client_subnet_id &&
      azapi_resource.private_test_vm[0].location == "germanywestcentral" &&
      output.private_hosted_agent.subnet_id == var.existing_private_network.agent_subnet_id
    )
    error_message = "Optional services must use their supplied network interfaces, without rebuilding shared foundation resources."
  }
  assert {
    condition = (
      output.private_probe_configuration.private_endpoint_subnet == null &&
      jsonencode(output.private_probe_configuration.private_endpoint_subnets.gateway) == jsonencode(["10.50.1.0/24"]) &&
      jsonencode(output.private_probe_configuration.private_endpoint_subnets.models) == jsonencode(["10.60.1.0/24"]) &&
      jsonencode(output.private_probe_configuration.private_endpoint_subnets.storage) == jsonencode(["10.80.1.0/24"])
    )
    error_message = "The probe must receive per-service ranges from the actual subnets, not the unused demo address space."
  }
}

run "platform_dns_without_competing_zone_groups" {
  command = plan
  variables {
    location                          = "germanywestcentral"
    enable_private_hosted_agent       = true
    enable_storage_private_endpoint   = true
    storage_public_network_access     = "Disabled"
    private_dns_zone_group_management = "platform"
    existing_private_network          = run.reuse_optional_agents_storage_and_client.private_network_configuration
  }
  assert {
    condition = (
      length(azapi_resource.private_dns_zone_group) == 0 &&
      length(azapi_resource.private_agent_dns_zone_group) == 0 &&
      length(azapi_resource.private_endpoint) == 3 &&
      length(azapi_resource.private_agent_endpoint) == 2 &&
      output.private_network_configuration.dns_zone_group_management == "platform" &&
      output.private_network_configuration.private_dns_zone_ids.registry == var.existing_private_network.private_dns_zone_ids.registry
    )
    error_message = "Platform-owned DNS must have one owner while keeping all enabled private endpoints and expected zone metadata."
  }
}

run "reject_missing_existing_network" {
  command = plan
  variables {
    existing_private_network = null
  }
  expect_failures = [var.existing_private_network]
}

run "reject_missing_endpoint_target" {
  command = plan
  variables {
    existing_private_network = merge(var.existing_private_network, {
      endpoint_subnet_ids = { gateway = var.existing_private_network.endpoint_subnet_ids.gateway }
    })
  }
  expect_failures = [var.existing_private_network]
}

run "reject_wrong_central_dns_zone" {
  command = plan
  variables {
    existing_private_network = merge(var.existing_private_network, {
      private_dns_zone_ids = merge(var.existing_private_network.private_dns_zone_ids, {
        openai = var.existing_private_network.private_dns_zone_ids.services
      })
    })
  }
  expect_failures = [var.existing_private_network]
}

run "reject_endpoint_in_another_subscription" {
  command = plan
  variables {
    existing_private_network = merge(var.existing_private_network, {
      endpoint_subnet_ids = merge(var.existing_private_network.endpoint_subnet_ids, {
        models = replace(
          var.existing_private_network.endpoint_subnet_ids.models,
          var.subscription_id,
          "00000000-0000-0000-0000-000000000002"
        )
      })
    })
  }
  expect_failures = [var.existing_private_network]
}

run "reject_client_in_another_subscription" {
  command = plan
  variables {
    enable_private_test_client         = true
    private_test_client_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleOnlyNotForDeployment"
    existing_private_network = merge(var.existing_private_network, {
      client_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/network-client/providers/Microsoft.Network/virtualNetworks/client/subnets/probe"
    })
  }
  expect_failures = [var.existing_private_network]
}

run "reject_unapproved_client_subnet" {
  command = plan
  variables {
    enable_private_test_client         = true
    private_test_client_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleOnlyNotForDeployment"
  }
  expect_failures = [var.existing_private_network]
}

run "reject_empty_client_subnet" {
  command = plan
  variables {
    enable_private_test_client         = true
    private_test_client_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleOnlyNotForDeployment"
    existing_private_network           = merge(var.existing_private_network, { client_subnet_id = "" })
  }
  expect_failures = [var.existing_private_network]
}

run "reject_integration_subnet_for_endpoints" {
  command = plan
  variables {
    existing_private_network = merge(var.existing_private_network, {
      endpoint_subnet_ids = merge(var.existing_private_network.endpoint_subnet_ids, {
        gateway = var.existing_private_network.gateway_subnet_id
      })
    })
  }
  expect_failures = [var.existing_private_network]
}

run "reject_gateway_region_mismatch" {
  command = plan
  override_data {
    target = data.azapi_resource.existing_private_vnet["gateway"]
    values = { output = { location = "eastus2" } }
  }
  expect_failures = [data.azapi_resource.existing_private_vnet["gateway"]]
}

run "reject_gateway_without_delegation" {
  command = plan
  override_data {
    target = data.azapi_resource.existing_private_subnet["gateway"]
    values = {
      output = {
        address_prefixes          = ["10.50.0.0/27"]
        delegations               = []
        network_security_group_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/network-gateway/providers/Microsoft.Network/networkSecurityGroups/gateway"
      }
    }
  }
  expect_failures = [data.azapi_resource.existing_private_subnet["gateway"]]
}

run "reject_undersized_gateway_subnet" {
  command = plan
  override_data {
    target = data.azapi_resource.existing_private_subnet["gateway"]
    values = {
      output = {
        address_prefixes          = ["10.50.0.0/28"]
        delegations               = ["Microsoft.Web/serverFarms"]
        network_security_group_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/network-gateway/providers/Microsoft.Network/networkSecurityGroups/gateway"
      }
    }
  }
  expect_failures = [data.azapi_resource.existing_private_subnet["gateway"]]
}

run "reject_gateway_without_nsg_metadata" {
  command = plan
  override_data {
    target = data.azapi_resource.existing_private_subnet["gateway"]
    values = { output = { address_prefixes = ["10.50.0.0/27"], delegations = ["Microsoft.Web/serverFarms"] } }
  }
  expect_failures = [data.azapi_resource.existing_private_subnet["gateway"]]
}

run "reject_gateway_with_null_nsg" {
  command = plan
  override_data {
    target = data.azapi_resource.existing_private_subnet["gateway"]
    values = {
      output = {
        address_prefixes          = ["10.50.0.0/27"]
        delegations               = ["Microsoft.Web/serverFarms"]
        network_security_group_id = null
      }
    }
  }
  expect_failures = [data.azapi_resource.existing_private_subnet["gateway"]]
}

run "reject_gateway_with_empty_nsg" {
  command = plan
  override_data {
    target = data.azapi_resource.existing_private_subnet["gateway"]
    values = {
      output = {
        address_prefixes          = ["10.50.0.0/27"]
        delegations               = ["Microsoft.Web/serverFarms"]
        network_security_group_id = ""
      }
    }
  }
  expect_failures = [data.azapi_resource.existing_private_subnet["gateway"]]
}

run "reject_delegated_endpoint_subnet" {
  command = plan
  override_data {
    target = data.azapi_resource.existing_private_subnet["endpoint_models"]
    values = { output = { address_prefixes = ["10.60.1.0/24"], delegations = ["Microsoft.Web/serverFarms"] } }
  }
  expect_failures = [data.azapi_resource.existing_private_subnet["endpoint_models"]]
}

run "reject_partial_subnet_metadata" {
  command = plan
  override_data {
    target = data.azapi_resource.existing_private_subnet["endpoint_models"]
    values = { output = { address_prefixes = ["10.60.1.0/24", null], delegations = [] } }
  }
  expect_failures = [data.azapi_resource.existing_private_subnet["endpoint_models"]]
}

run "reject_undersized_agent_subnet" {
  command = plan
  variables {
    location                    = "germanywestcentral"
    enable_private_hosted_agent = true
    existing_private_network    = run.reuse_optional_agents_storage_and_client.private_network_configuration
  }
  override_data {
    target = data.azapi_resource.existing_private_subnet["agents"]
    values = { output = { address_prefixes = ["10.70.0.0/28"], delegations = ["Microsoft.App/environments"] } }
  }
  expect_failures = [data.azapi_resource.existing_private_subnet["agents"]]
}

run "reject_agent_prefix_crossing_rfc1918_boundary" {
  command = plan
  variables {
    location                    = "germanywestcentral"
    enable_private_hosted_agent = true
    existing_private_network    = run.reuse_optional_agents_storage_and_client.private_network_configuration
  }
  override_data {
    target = data.azapi_resource.existing_private_subnet["agents"]
    values = { output = { address_prefixes = ["10.0.0.0/7"], delegations = ["Microsoft.App/environments"] } }
  }
  expect_failures = [data.azapi_resource.existing_private_subnet["agents"]]
}

run "reject_existing_without_private_networking" {
  command = plan
  variables {
    enable_private_networking     = false
    gateway_public_network_access = "Enabled"
    models_public_network_access  = "Enabled"
  }
  expect_failures = [var.private_network_mode]
}

run "reject_platform_dns_for_created_foundation" {
  command = plan
  variables {
    private_network_mode              = "create"
    existing_private_network          = null
    private_dns_zone_group_management = "platform"
  }
  expect_failures = [var.private_dns_zone_group_management]
}
