mock_provider "azapi" {}

variables {
  subscription_id                          = "00000000-0000-0000-0000-000000000001"
  environment_name                         = "private-fixture"
  location                                 = "swedencentral"
  gateway_location                         = "swedencentral"
  gateway_contract                         = "2026"
  api2026_resource_group_name              = "single-fixture"
  api2026_private_lab_enabled              = true
  api2026_private_lab_ssh_public_key       = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA synthetic-only"
  standalone_backend_public_network_access = "Disabled"
  model_deployments                        = jsondecode(file("api2026gateway/model-profile.json")).model_deployments
  model_aliases                            = jsondecode(file("api2026gateway/model-profile.json")).model_aliases
}

run "single_group_without_private_lab" {
  command = plan
  variables {
    api2026_private_lab_enabled              = false
    api2026_private_lab_ssh_public_key       = null
    standalone_backend_public_network_access = null
    retain_legacy_resource_groups            = true
  }
  override_resource {
    target          = azapi_resource.resource_group["gateway"]
    override_during = plan
    values          = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/single-fixture" }
  }
  assert {
    condition = (
      toset(keys(azapi_resource.resource_group)) == toset(["gateway"]) &&
      length(data.azapi_resource.existing_resource_group) == 0 &&
      alltrue([for name in values(output.resource_groups) : name == var.api2026_resource_group_name]) &&
      alltrue([for resource in [
        azapi_resource.models, azapi_resource.agents, azapi_resource.storage, azapi_resource.registry,
        azapi_resource.logs["gateway"], azapi_resource.logs["agents"],
        azapi_resource.insights["gateway"], azapi_resource.insights["agents"]
      ] : resource.parent_id == azapi_resource.resource_group["gateway"].id]) &&
      length(azapi_resource.api2026_vnet) == 0 &&
      length(azapi_update_resource.disk_access) == 0 &&
      output.api2026_private_lab == null
    )
    error_message = "Exact-name mode must have one physical owner with every workload routed to it, independently of the legacy retention switch."
  }
}

run "existing_resource_group_is_read_not_managed" {
  command = plan
  variables {
    api2026_private_lab_enabled              = false
    api2026_private_lab_ssh_public_key       = null
    standalone_backend_public_network_access = null
    retain_legacy_resource_groups            = true
    api2026_existing_resource_group          = true
  }
  override_data {
    target = data.azapi_resource.existing_resource_group[0]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/single-fixture" }
  }
  assert {
    condition = (
      length(azapi_resource.resource_group) == 0 &&
      length(data.azapi_resource.existing_resource_group) == 1 &&
      data.azapi_resource.existing_resource_group[0].type == "Microsoft.Resources/resourceGroups@2021-04-01" &&
      data.azapi_resource.existing_resource_group[0].name == var.api2026_resource_group_name &&
      data.azapi_resource.existing_resource_group[0].parent_id == "/subscriptions/${var.subscription_id}" &&
      output.gateway_contract.single_resource_group &&
      output.gateway_contract.existing_resource_group &&
      output.resource_group_name == var.api2026_resource_group_name &&
      alltrue([for name in values(output.resource_groups) : name == var.api2026_resource_group_name]) &&
      alltrue([for resource in [
        azapi_resource.gateway, azapi_resource.models, azapi_resource.agents, azapi_resource.storage, azapi_resource.registry,
        azapi_resource.logs["gateway"], azapi_resource.logs["agents"],
        azapi_resource.insights["gateway"], azapi_resource.insights["agents"]
      ] : resource.parent_id == data.azapi_resource.existing_resource_group[0].id]) &&
      length(azapi_resource.api2026_vnet) == 0 &&
      output.api2026_private_lab == null
    )
    error_message = "Existing-group mode must read, never create, the named RG and place every workload in it, independently of the legacy retention switch."
  }
}

run "private_lab_composes_before_subnet_and_identity_ids_exist" {
  command = plan
  assert {
    condition = (
      toset(keys(azapi_resource.resource_group)) == toset(["gateway"]) &&
      length(data.azapi_resource.gateway_backend_subnet) == 0 &&
      length(data.azapi_resource.gateway_backend_vnet) == 0 &&
      contains(keys(azapi_resource.gateway.body.properties), "backend") &&
      !can(azapi_resource.gateway.body.sku) &&
      !can(azapi_resource.gateway.body.properties.publicNetworkAccess) &&
      length(azapi_resource.api2026_subnet) == 3 &&
      length(azapi_resource.api2026_private_endpoint) == 5 &&
      length(azapi_resource.api2026_dns_zone) == 9 &&
      length(azapi_resource.api2026_dns_link) == 9 &&
      length(azapi_resource.api2026_dns_group) == 5 &&
      length(azapi_resource.api2026_monitor_resource) == 4 &&
      length(azapi_resource.api2026_identity) == 2 &&
      length(azapi_resource.api2026_client_grant) == 11 &&
      length(azapi_resource.role_assignment) == 6 &&
      length(azapi_update_resource.disk_access) == 1
    )
    error_message = "Computed new IDs must not control for_each/count or invoke the external-subnet reader; the full one-authority lab must compose before apply."
  }
  assert {
    condition = (
      azapi_resource.api2026_subnet["gateway-outbound"].body.properties.delegations[0].properties.serviceName == "Microsoft.App/environments" &&
      azapi_resource.api2026_subnet["private-endpoints"].body.properties.privateEndpointNetworkPolicies == "Disabled" &&
      !azapi_resource.api2026_subnet["verification-client"].body.properties.defaultOutboundAccess &&
      length(azapi_resource.api2026_nsg["gateway"].body.properties.securityRules) == 0 &&
      length(azapi_resource.api2026_nsg["client"].body.properties.securityRules) == 7 &&
      azapi_resource.api2026_ampls["lab"].body.properties.accessModeSettings.ingestionAccessMode == "PrivateOnly" &&
      azapi_resource.api2026_ampls["lab"].body.properties.accessModeSettings.queryAccessMode == "PrivateOnly" &&
      alltrue([for resource in [azapi_resource.models, azapi_resource.agents, azapi_resource.storage, azapi_resource.registry] :
        resource.body.properties.publicNetworkAccess == "Disabled"
      ]) &&
      azapi_resource.storage.body.properties.networkAcls.bypass == "None" &&
      length(azapi_resource.storage.body.properties.networkAcls.resourceAccessRules) == 0 &&
      try(length(azapi_resource.storage.ignore_body_changes), 0) == 0 &&
      azapi_resource.models.body.properties.disableLocalAuth &&
      azapi_resource.agents.body.properties.disableLocalAuth &&
      !azapi_resource.storage.body.properties.allowSharedKeyAccess &&
      azapi_resource.foundry_provider.body.properties.foundry.authentication.managedIdentity.resource == "https://cognitiveservices.azure.com/"
    )
    error_message = "The new private lab must bind the correct delegation/egress/AMPLS controls and preserve MI without carrying old Storage exceptions."
  }
  assert {
    condition = (
      azapi_resource.api2026_vm["client"].body.properties.osProfile.linuxConfiguration.disablePasswordAuthentication &&
      !can(azapi_resource.api2026_vm["client"].body.properties.osProfile.adminPassword) &&
      azapi_resource.api2026_vm["client"].body.properties.osProfile.linuxConfiguration.ssh.publicKeys[0].keyData == var.api2026_private_lab_ssh_public_key &&
      azapi_resource.api2026_vm["client"].body.properties.securityProfile.securityType == "TrustedLaunch" &&
      azapi_resource.api2026_vm["client"].body.properties.securityProfile.uefiSettings.secureBootEnabled &&
      azapi_resource.api2026_vm["client"].body.properties.securityProfile.uefiSettings.vTpmEnabled &&
      !can(azapi_resource.api2026_nic["client"].body.properties.ipConfigurations[0].properties.publicIPAddress) &&
      azapi_update_resource.disk_access["client"].body.properties.networkAccessPolicy == "DenyAll" &&
      azapi_update_resource.disk_access["client"].body.properties.publicNetworkAccess == "Disabled" &&
      azapi_resource.api2026_container["lab"].body.properties.publicAccess == "None" &&
      [for log in azapi_resource.api2026_blob_read_diagnostics["lab"].body.properties.logs : log.category if log.enabled] == ["StorageRead"]
    )
    error_message = "The verification VM must use supplied public material only, private networking, Trusted Launch and a tracked native disk restriction; diagnostics enable only StorageRead."
  }
}

run "private_client_grants_never_use_negative_identity" {
  command = plan
  override_resource {
    target          = azapi_resource.api2026_identity["positive"]
    override_during = plan
    values = {
      id     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/single-fixture/providers/Microsoft.ManagedIdentity/userAssignedIdentities/positive"
      output = { properties = { principalId = "00000000-0000-0000-0000-000000000021", clientId = "00000000-0000-0000-0000-000000000031", tenantId = "00000000-0000-0000-0000-000000000003" } }
    }
  }
  override_resource {
    target          = azapi_resource.api2026_identity["negative"]
    override_during = plan
    values = {
      id     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/single-fixture/providers/Microsoft.ManagedIdentity/userAssignedIdentities/negative"
      output = { properties = { principalId = "00000000-0000-0000-0000-000000000022", clientId = "00000000-0000-0000-0000-000000000032", tenantId = "00000000-0000-0000-0000-000000000003" } }
    }
  }
  assert {
    condition = alltrue([for grant in azapi_resource.api2026_client_grant :
      grant.body.properties.principalId == azapi_resource.api2026_identity["positive"].output.properties.principalId &&
      grant.body.properties.principalId != azapi_resource.api2026_identity["negative"].output.properties.principalId
    ])
    error_message = "Every client grant must use the positive identity; the fresh negative identity must receive no configured grant."
  }
}

run "reject_empty_exact_group" {
  command = plan
  variables { api2026_resource_group_name = "" }
  expect_failures = [var.api2026_resource_group_name]
}

run "reject_invalid_exact_group" {
  command = plan
  variables { api2026_resource_group_name = "not/a/group" }
  expect_failures = [var.api2026_resource_group_name]
}

run "reject_trailing_period_group" {
  command = plan
  variables { api2026_resource_group_name = "invalid." }
  expect_failures = [var.api2026_resource_group_name]
}

run "reject_private_lab_without_single_owner" {
  command = plan
  variables { api2026_resource_group_name = null }
  expect_failures = [var.api2026_private_lab_enabled]
}

run "reject_private_lab_with_external_subnet" {
  command = plan
  variables {
    gateway_backend_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/network/providers/Microsoft.Network/virtualNetworks/existing/subnets/gateway"
  }
  expect_failures = [var.api2026_private_lab_enabled]
}

run "reject_private_lab_region_split" {
  command = plan
  variables { gateway_location = "eastus2" }
  expect_failures = [var.api2026_private_lab_enabled]
}

run "reject_private_lab_public_backends" {
  command = plan
  variables { standalone_backend_public_network_access = "Enabled" }
  expect_failures = [var.standalone_backend_public_network_access]
}

run "reject_private_lab_unspecified_backends" {
  command = plan
  variables { standalone_backend_public_network_access = null }
  expect_failures = [var.standalone_backend_public_network_access]
}

run "reject_missing_public_key" {
  command = plan
  variables { api2026_private_lab_ssh_public_key = null }
  expect_failures = [var.api2026_private_lab_ssh_public_key]
}

run "reject_non_public_key_material" {
  command = plan
  variables { api2026_private_lab_ssh_public_key = "not-an-openssh-public-key" }
  expect_failures = [var.api2026_private_lab_ssh_public_key]
}

run "reject_unused_public_key" {
  command = plan
  variables {
    api2026_private_lab_enabled              = false
    standalone_backend_public_network_access = null
  }
  expect_failures = [var.api2026_private_lab_ssh_public_key]
}

run "reject_exact_group_for_legacy_contract" {
  command = plan
  variables {
    gateway_contract                         = "legacy"
    api2026_private_lab_enabled              = false
    api2026_private_lab_ssh_public_key       = null
    standalone_backend_public_network_access = null
    model_aliases                            = null
    publisher_email                          = "fixture@example.test"
    model_deployments = {
      model = { model_name = "gpt-5.4-mini", model_version = "2026-03-17", capacity = 1, token_limit = 100 }
    }
  }
  expect_failures = [var.api2026_resource_group_name]
}

run "reject_existing_group_with_private_lab" {
  command = plan
  variables { api2026_existing_resource_group = true }
  override_data {
    target = data.azapi_resource.existing_resource_group[0]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/single-fixture" }
  }
  expect_failures = [var.api2026_existing_resource_group]
}

run "reject_existing_group_without_name" {
  command = plan
  variables {
    api2026_resource_group_name              = null
    api2026_existing_resource_group          = true
    api2026_private_lab_enabled              = false
    api2026_private_lab_ssh_public_key       = null
    standalone_backend_public_network_access = null
  }
  expect_failures = [var.api2026_existing_resource_group]
}
