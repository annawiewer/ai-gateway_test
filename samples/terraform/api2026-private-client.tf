locals {
  api2026_client_vm_name   = "vm-${local.resource_token}-client"
  api2026_client_disk_name = "os-${local.resource_token}-client"
  api2026_client_grants = var.api2026_private_lab_enabled ? {
    models                  = { scope = azapi_resource.models.id, role = "5e0bd9bd-7b93-4f28-af87-19fc36ad61bd" }
    project                 = { scope = azapi_resource.project.id, role = "a97b65f3-24c7-4388-baec-2e87135dc908" }
    blob                    = { scope = azapi_resource.api2026_container["lab"].id, role = "ba92f5b4-2d11-453d-a403-e96b0029c9fe" }
    registry                = { scope = azapi_resource.registry.id, role = "8311e382-0749-4cb8-b61a-304f252e45ec" }
    gateway                 = { scope = azapi_resource.gateway.id, role = "a6b68e3d-a1f0-4c60-8678-237c050cf4ea" }
    gateway-query           = { scope = azapi_resource.logs["gateway"].id, role = "73c42c96-874c-492b-b04d-ab87d138a893" }
    agents-query            = { scope = azapi_resource.logs["agents"].id, role = "73c42c96-874c-492b-b04d-ab87d138a893" }
    gateway-monitor-read    = { scope = azapi_resource.insights["gateway"].id, role = "43d0d8ad-25c7-4714-9337-8ba259a9fe05" }
    agents-monitor-read     = { scope = azapi_resource.insights["agents"].id, role = "43d0d8ad-25c7-4714-9337-8ba259a9fe05" }
    gateway-monitor-publish = { scope = azapi_resource.insights["gateway"].id, role = "3913510d-42f4-4e42-8a64-420c390055eb" }
    agents-monitor-publish  = { scope = azapi_resource.insights["agents"].id, role = "3913510d-42f4-4e42-8a64-420c390055eb" }
  } : {}
}

resource "azapi_resource" "api2026_identity" {
  for_each               = var.api2026_private_lab_enabled ? toset(["positive", "negative"]) : toset([])
  type                   = "Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31"
  name                   = "id-${local.resource_token}-${each.key}"
  parent_id              = azapi_resource.resource_group["gateway"].id
  location               = var.location
  tags                   = local.tags
  body                   = {}
  response_export_values = ["properties.principalId", "properties.clientId", "properties.tenantId"]
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "api2026_nic" {
  for_each  = var.api2026_private_lab_enabled ? toset(["client"]) : toset([])
  type      = "Microsoft.Network/networkInterfaces@2024-05-01"
  name      = "nic-${local.resource_token}-client"
  parent_id = azapi_resource.resource_group["gateway"].id
  location  = var.location
  tags      = local.tags
  body = {
    properties = {
      enableAcceleratedNetworking = true
      enableIPForwarding          = false
      ipConfigurations = [{
        name = "private"
        properties = {
          primary                   = true
          privateIPAddressVersion   = "IPv4"
          privateIPAllocationMethod = "Static"
          privateIPAddress          = "10.244.2.4"
          subnet                    = { id = azapi_resource.api2026_subnet["verification-client"].id }
        }
      }]
    }
  }
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "api2026_vm" {
  for_each  = var.api2026_private_lab_enabled ? toset(["client"]) : toset([])
  type      = "Microsoft.Compute/virtualMachines@2024-07-01"
  name      = local.api2026_client_vm_name
  parent_id = azapi_resource.resource_group["gateway"].id
  location  = var.location
  tags      = local.tags
  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [for identity in azapi_resource.api2026_identity : identity.id]
  }
  body = {
    properties = {
      hardwareProfile = { vmSize = "Standard_D2s_v5" }
      storageProfile = {
        imageReference = {
          publisher = "Canonical"
          offer     = "ubuntu-24_04-lts"
          sku       = "server"
          version   = "24.04.202610210"
        }
        osDisk = {
          name         = local.api2026_client_disk_name
          createOption = "FromImage"
          deleteOption = "Detach"
          caching      = "ReadWrite"
          managedDisk  = { storageAccountType = "Premium_LRS" }
        }
      }
      osProfile = {
        computerName             = local.api2026_client_vm_name
        adminUsername            = "aigwverify"
        allowExtensionOperations = true
        linuxConfiguration = {
          disablePasswordAuthentication = true
          provisionVMAgent              = true
          ssh = {
            publicKeys = [{
              path    = "/home/aigwverify/.ssh/authorized_keys"
              keyData = try(trimspace(var.api2026_private_lab_ssh_public_key), "")
            }]
          }
        }
      }
      networkProfile = {
        networkInterfaces = [{
          id         = azapi_resource.api2026_nic[each.key].id
          properties = { primary = true, deleteOption = "Detach" }
        }]
      }
      securityProfile = {
        securityType = "TrustedLaunch"
        uefiSettings = { secureBootEnabled = true, vTpmEnabled = true }
      }
      diagnosticsProfile = { bootDiagnostics = { enabled = false } }
    }
  }
  response_export_values = ["properties.storageProfile.osDisk.managedDisk.id"]
  lifecycle { prevent_destroy = true }
  timeouts { create = "20m" }
}

resource "azapi_update_resource" "disk_access" {
  for_each    = var.api2026_private_lab_enabled ? toset(["client"]) : toset([])
  type        = "Microsoft.Compute/disks@2024-03-02"
  resource_id = azapi_resource.api2026_vm[each.key].output.properties.storageProfile.osDisk.managedDisk.id
  body = {
    properties = {
      networkAccessPolicy = "DenyAll"
      publicNetworkAccess = "Disabled"
    }
  }
  response_export_values = ["properties.networkAccessPolicy", "properties.publicNetworkAccess"]
  lifecycle {
    prevent_destroy = true
    precondition {
      condition = lower(azapi_resource.api2026_vm[each.key].output.properties.storageProfile.osDisk.managedDisk.id) == lower(
        "${azapi_resource.resource_group["gateway"].id}/providers/Microsoft.Compute/disks/${local.api2026_client_disk_name}"
      )
      error_message = "Only this fresh verification VM's exact OS disk may receive the export-access restriction."
    }
  }
}

resource "azapi_resource" "api2026_container" {
  for_each  = local.api2026_lab_keys
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = "private-verification"
  parent_id = "${azapi_resource.storage.id}/blobServices/default"
  body = {
    properties = {
      publicAccess = "None"
      metadata     = { purpose = "bounded-private-verification" }
    }
  }
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "api2026_client_grant" {
  for_each  = local.api2026_client_grants
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("url", "${each.value.scope}/${azapi_resource.api2026_identity["positive"].output.properties.principalId}/${each.value.role}")
  parent_id = each.value.scope
  body = {
    properties = {
      roleDefinitionId = "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/${each.value.role}"
      principalId      = azapi_resource.api2026_identity["positive"].output.properties.principalId
      principalType    = "ServicePrincipal"
    }
  }
  lifecycle { prevent_destroy = true }
}

resource "azapi_resource" "api2026_blob_read_diagnostics" {
  for_each  = local.api2026_lab_keys
  type      = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  name      = "blob-read"
  parent_id = "${azapi_resource.storage.id}/blobServices/default"
  body = {
    properties = {
      workspaceId                 = azapi_resource.logs["gateway"].id
      logAnalyticsDestinationType = "Dedicated"
      logs = [for category in ["StorageRead", "StorageWrite", "StorageDelete"] : {
        category        = category
        categoryGroup   = null
        enabled         = category == "StorageRead"
        retentionPolicy = { enabled = false, days = 0 }
      }]
      metrics = [for category in ["Capacity", "Transaction"] : {
        category        = category
        enabled         = false
        retentionPolicy = { enabled = false, days = 0 }
      }]
    }
  }
  create_headers = { "If-None-Match" = "*" }
  lifecycle { prevent_destroy = true }
}

output "api2026_private_lab" {
  description = "Owned private-lab resource IDs and public identity metadata, not private traffic, authentication, telemetry or gateway-ingress proof."
  value = var.api2026_private_lab_enabled ? {
    vnet_id           = azapi_resource.api2026_vnet["lab"].id
    subnet_ids        = { for key, subnet in azapi_resource.api2026_subnet : key => subnet.id }
    private_endpoints = { for key, endpoint in azapi_resource.api2026_private_endpoint : key => endpoint.id }
    dns_zones         = { for key, zone in azapi_resource.api2026_dns_zone : key => zone.id }
    ampls_id          = azapi_resource.api2026_ampls["lab"].id
    client_vm_id      = azapi_resource.api2026_vm["client"].id
    client_private_ip = "10.244.2.4"
    os_disk_id        = azapi_update_resource.disk_access["client"].resource_id
    identities = { for key, identity in azapi_resource.api2026_identity : key => {
      id           = identity.id
      principal_id = identity.output.properties.principalId
      client_id    = identity.output.properties.clientId
      tenant_id    = identity.output.properties.tenantId
    } }
    container_id               = azapi_resource.api2026_container["lab"].id
    storage_read_diagnostic_id = azapi_resource.api2026_blob_read_diagnostics["lab"].id
  } : null
}
