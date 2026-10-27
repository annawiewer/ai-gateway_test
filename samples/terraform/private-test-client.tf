resource "azapi_resource" "private_test_nic" {
  count     = var.enable_private_test_client ? 1 : 0
  type      = "Microsoft.Network/networkInterfaces@2024-05-01"
  name      = "${local.names.gateway}-test-nic"
  parent_id = azapi_resource.resource_group["gateway"].id
  location  = local.private_client_location
  tags      = local.tags
  body = {
    properties = {
      ipConfigurations = [{
        name = "private"
        properties = {
          privateIPAllocationMethod = "Dynamic"
          subnet                    = { id = local.private_client_subnet_id }
        }
      }]
    }
  }
}

resource "azapi_resource" "private_test_vm" {
  count     = var.enable_private_test_client ? 1 : 0
  type      = "Microsoft.Compute/virtualMachines@2024-07-01"
  name      = "${local.names.gateway}-test"
  parent_id = azapi_resource.resource_group["gateway"].id
  location  = local.private_client_location
  tags      = local.tags
  identity { type = "SystemAssigned" }
  body = {
    properties = {
      hardwareProfile = { vmSize = var.private_test_client_vm_size }
      storageProfile = {
        imageReference = {
          publisher = "Canonical"
          offer     = "0001-com-ubuntu-server-jammy"
          sku       = "22_04-lts-gen2"
          version   = "latest"
        }
        osDisk = {
          createOption = "FromImage"
          deleteOption = "Delete"
          managedDisk  = { storageAccountType = "StandardSSD_LRS" }
        }
      }
      osProfile = {
        computerName  = "gateway-test"
        adminUsername = "azureuser"
        linuxConfiguration = {
          disablePasswordAuthentication = true
          provisionVMAgent              = true
          ssh = {
            publicKeys = [{
              path    = "/home/azureuser/.ssh/authorized_keys"
              keyData = trimspace(var.private_test_client_ssh_public_key)
            }]
          }
        }
      }
      networkProfile = {
        networkInterfaces = [{
          id         = azapi_resource.private_test_nic[0].id
          properties = { primary = true, deleteOption = "Detach" }
        }]
      }
      securityProfile = {
        securityType = "TrustedLaunch"
        uefiSettings = { secureBootEnabled = true, vTpmEnabled = true }
      }
    }
  }
}

resource "azapi_resource" "private_test_key_role" {
  count     = var.enable_private_test_client ? 1 : 0
  type      = "Microsoft.Authorization/roleDefinitions@2022-04-01"
  name      = uuidv5("url", "${azapi_resource.resource_group["gateway"].id}/private-test-key-reader")
  parent_id = local.subscription_scope
  body = {
    properties = {
      roleName         = "AI Gateway PoC key reader ${local.resource_token}"
      description      = "Only retrieve gateway runtime keys for the isolated private-path proof client."
      type             = "CustomRole"
      assignableScopes = [azapi_resource.resource_group["gateway"].id]
      permissions = [{
        actions        = ["Microsoft.ApiManagement/service/apiKeys/listSecrets/action"]
        notActions     = []
        dataActions    = []
        notDataActions = []
      }]
    }
  }
}

resource "azapi_resource" "private_test_key_binding" {
  count     = var.enable_private_test_client ? 1 : 0
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("url", "${azapi_resource.gateway.id}/${azapi_resource.private_test_vm[0].identity[0].principal_id}/private-test-key-reader")
  parent_id = azapi_resource.gateway.id
  body = {
    properties = {
      principalId      = azapi_resource.private_test_vm[0].identity[0].principal_id
      principalType    = "ServicePrincipal"
      roleDefinitionId = azapi_resource.private_test_key_role[0].id
    }
  }
}

resource "azapi_resource" "private_test_storage_binding" {
  count     = var.enable_private_test_client && var.enable_storage_private_endpoint ? 1 : 0
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("url", "${azapi_resource.storage.id}/${azapi_resource.private_test_vm[0].identity[0].principal_id}/private-test-blob-reader")
  parent_id = azapi_resource.storage.id
  body = {
    properties = {
      principalId      = azapi_resource.private_test_vm[0].identity[0].principal_id
      principalType    = "ServicePrincipal"
      roleDefinitionId = "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/2a2b9908-6ea1-4ae2-8e65-a410df84e7d1"
    }
  }
}
