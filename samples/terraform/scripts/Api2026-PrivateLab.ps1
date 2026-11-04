# Dot-sourced by the scoped acceptance checker; all reads use its admitted IDs and explicit subscription.

function Assert-LabBody([string]$Name, [string]$Key, $Actual, $Expected, [switch]$Live) {
    Assert-Map $Actual "$Name body"
    $actualCopy = $Actual | ConvertTo-Json -Depth 40 | ConvertFrom-Json -AsHashtable -Depth 40
    $expectedCopy = $Expected | ConvertTo-Json -Depth 40 | ConvertFrom-Json -AsHashtable -Depth 40
    $externalNsg = $Live -and $Name -ceq 'api2026_subnet' -and $Key -ceq 'private-endpoints' -and $ExpectedPrivateEndpointSubnetNsgId
    if ($externalNsg) {
        $expectedCopy.properties.networkSecurityGroup = @{ id = $ExpectedPrivateEndpointSubnetNsgId }
    }
    if ($Live -and $Name -ceq 'api2026_blob_read_diagnostics' -and
        $expectedCopy.properties.logAnalyticsDestinationType -ceq 'Dedicated' -and
        $actualCopy.properties.Contains('logAnalyticsDestinationType') -and
        $null -eq $actualCopy.properties.logAnalyticsDestinationType) {
        $expectedCopy.properties.logAnalyticsDestinationType = $null
        $readbackProjections.Add(@{ resource = "$Name/$Key"; field = 'logAnalyticsDestinationType'; detail = 'Service returned null for configured Dedicated; exact workspace and categories checked. Resource-specific table delivery requires a separate query.' })
    }
    $unordered = switch ($Name) {
        'api2026_nsg' { @{ securityRules = 'name' } }
        'api2026_dns_group' { @{ privateDnsZoneConfigs = 'name' } }
        'api2026_blob_read_diagnostics' { @{ logs = 'category'; metrics = 'category' } }
        default { @{} }
    }
    foreach ($field in $unordered.Keys) {
        if ($actualCopy.properties[$field] -isnot [array]) { Stop-Api2026 "Missing private-lab array: $Name.$field." }
        $actualCopy.properties[$field] = @($actualCopy.properties[$field] | Sort-Object -Property { $_[$unordered[$field]] })
        $expectedCopy.properties[$field] = @($expectedCopy.properties[$field] | Sort-Object -Property { $_[$unordered[$field]] })
    }
    Assert-ConfiguredValue $actualCopy $expectedCopy "private lab $Name/$Key"
    $properties = $Actual.properties
    switch ($Name) {
        'api2026_vnet' {
            if ($properties.virtualNetworkPeerings) { Stop-Api2026 'Private lab must remain unpeered.' }
        }
        'api2026_nat' {
            if ($properties.publicIpPrefixes) { Stop-Api2026 'Private lab permits only its one owned NAT public IP.' }
        }
        'api2026_subnet' {
            if ($properties.routeTable -or $properties.serviceEndpoints -or $properties.serviceEndpointPolicies -or
                ($Key -cne 'verification-client' -and $properties.natGateway) -or
                ($Key -ceq 'private-endpoints' -and $properties.networkSecurityGroup -and -not $externalNsg)) {
                Stop-Api2026 'Unexpected routing, service endpoint or network attachment on an owned lab subnet.'
            }
        }
        'api2026_private_endpoint' {
            if ($properties.manualPrivateLinkServiceConnections) { Stop-Api2026 'Unexpected manual private endpoint connection.' }
        }
        'api2026_nic' {
            if ($properties.dnsSettings.dnsServers -or
                @($properties.ipConfigurations | Where-Object { $_.properties.publicIPAddress }).Count) {
                Stop-Api2026 'Verification NIC must use private addressing and Azure DNS, without a public IP.'
            }
        }
        'api2026_vm' {
            if ($properties.osProfile.adminPassword -or $properties.storageProfile.dataDisks) {
                Stop-Api2026 'Verification VM must not introduce a password or additional disks.'
            }
        }
        'api2026_client_grant' {
            if ($properties.condition -or $properties.delegatedManagedIdentityResourceId) {
                Stop-Api2026 'Unexpected conditional or delegated private-client grant.'
            }
        }
        'api2026_blob_read_diagnostics' {
            if ($properties.storageAccountId -or $properties.eventHubAuthorizationRuleId -or $properties.eventHubName -or
                $properties.serviceBusRuleId -or $properties.marketplacePartnerId) {
                Stop-Api2026 'StorageRead diagnostics must use only the owned gateway workspace.'
            }
        }
    }
}

function Add-LabResource(
    [string]$Name, [string]$Key, [string]$Type, [string]$Parent, [hashtable]$Body,
    [string]$Id = '', [string]$TerraformType = 'azapi_resource'
) {
    $value = Get-StateValue $Name $Key $TerraformType
    if (-not $Id) {
        Assert-Name $value.name
        $Id = "$Parent/providers/$($Type.Split('@')[0])/$($value.name)"
    }
    $value = Register-Resource $Name $Key $Type $Id $Parent $TerraformType
    if ($TerraformType -ceq 'azapi_resource' -and
        ($Parent -ieq $groupIds.gateway -or $Name -ceq 'api2026_dns_link')) {
        $region = if ($Name -in @('api2026_ampls', 'api2026_dns_zone', 'api2026_dns_link')) { 'global' } else { $gatewayState.location }
        if (-not $value.location -or $value.location.Replace(' ', '') -ine $region.Replace(' ', '')) {
            Stop-Api2026 "Private-lab region mismatch: $Name."
        }
    }
    Assert-LabBody $Name $Key $value.body $Body
    $script:labResources[(Get-Address $Name $Key $TerraformType)] = @{
        name = $Name; key = $Key; terraformType = $TerraformType; body = $Body
    }
    $value
}

function Register-Api2026PrivateLab {
    $script:labResources = @{}
    $script:lab = @{ subnets = @{}; endpoints = @{}; zones = @{}; identities = @{} }
    if ($ExpectedPrivateEndpointSubnetNsgId -and @($stateByAddress.Values | Where-Object {
        $_.values.id -ieq $ExpectedPrivateEndpointSubnetNsgId
    }).Count) {
        Stop-Api2026 'The explicitly external private-endpoint NSG must not be Terraform-managed.'
    }
    $group = $groupIds.gateway
    $lab.vnet = Add-LabResource api2026_vnet lab 'Microsoft.Network/virtualNetworks@2024-05-01' $group @{
        properties = @{ addressSpace = @{ addressPrefixes = @('10.244.0.0/16') }; dhcpOptions = @{ dnsServers = @() } }
    }
    $gatewayNsg = Add-LabResource api2026_nsg gateway 'Microsoft.Network/networkSecurityGroups@2024-05-01' $group @{
        properties = @{ securityRules = @() }
    }
    $rules = @(
        foreach ($rule in @(
            @('dns', 100, '*', '168.63.129.16', @('53')),
            @('platform', 110, 'Tcp', '168.63.129.16', @('80', '32526')),
            @('identity', 120, 'Tcp', '169.254.169.254', @('80')),
            @('private-https', 130, 'Tcp', '10.244.1.0/24', @('443')),
            @('azure-control-https', 140, 'Tcp', 'AzureCloud', @('443'))
        )) {
            @{ name = "allow-$($rule[0])"; properties = @{
                priority = $rule[1]; access = 'Allow'; direction = 'Outbound'; protocol = $rule[2]
                sourcePortRange = '*'; sourceAddressPrefix = '*'; destinationAddressPrefix = $rule[3]; destinationPortRanges = $rule[4]
            } }
        }
        foreach ($direction in @('Inbound', 'Outbound')) {
            @{ name = "deny-other-$($direction.ToLowerInvariant())"; properties = @{
                priority = 4096; access = 'Deny'; direction = $direction; protocol = '*'
                sourcePortRange = '*'; sourceAddressPrefix = '*'; destinationAddressPrefix = '*'; destinationPortRange = '*'
            } }
        }
    )
    $clientNsg = Add-LabResource api2026_nsg client 'Microsoft.Network/networkSecurityGroups@2024-05-01' $group @{
        properties = @{ securityRules = $rules }
    }
    $natIp = Add-LabResource api2026_nat_ip client 'Microsoft.Network/publicIPAddresses@2024-05-01' $group @{
        sku = @{ name = 'Standard'; tier = 'Regional' }
        properties = @{ publicIPAllocationMethod = 'Static'; publicIPAddressVersion = 'IPv4' }
    }
    $nat = Add-LabResource api2026_nat client 'Microsoft.Network/natGateways@2024-05-01' $group @{
        sku = @{ name = 'Standard' }; properties = @{ idleTimeoutInMinutes = 4; publicIpAddresses = @(@{ id = $natIp.id }) }
    }
    $subnets = @{
        'gateway-outbound' = @{
            addressPrefix = '10.244.0.0/24'; networkSecurityGroup = @{ id = $gatewayNsg.id }
            delegations = @(@{ name = 'gateway-integration'; properties = @{ serviceName = 'Microsoft.App/environments' } })
        }
        'private-endpoints' = @{ addressPrefix = '10.244.1.0/24'; delegations = @(); privateEndpointNetworkPolicies = 'Disabled' }
        'verification-client' = @{
            addressPrefix = '10.244.2.0/24'; defaultOutboundAccess = $false
            natGateway = @{ id = $nat.id }; networkSecurityGroup = @{ id = $clientNsg.id }
        }
    }
    foreach ($key in $subnets.Keys) {
        $lab.subnets[$key] = Add-LabResource api2026_subnet $key 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' $lab.vnet.id @{
            properties = $subnets[$key]
        } -Id "$($lab.vnet.id)/subnets/$key"
    }
    Assert-ConfiguredValue $contract.backend_subnet_id $lab.subnets['gateway-outbound'].id 'owned gateway creation subnet'
    $lab.ampls = Add-LabResource api2026_ampls lab 'Microsoft.Insights/privateLinkScopes@2021-09-01' $group @{
        properties = @{ accessModeSettings = @{ ingestionAccessMode = 'PrivateOnly'; queryAccessMode = 'PrivateOnly'; exclusions = @() } }
    }
    foreach ($key in @('gateway', 'agents')) {
        foreach ($kind in @('logs', 'insights')) {
            $null = Add-LabResource api2026_monitor_resource "$key-$kind" 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01' $lab.ampls.id @{
                properties = @{ linkedResourceId = (Get-StateValue $kind $key).id }
            } -Id "$($lab.ampls.id)/scopedResources/$key-$kind"
        }
    }
    $cognitiveZones = @('privatelink.cognitiveservices.azure.com', 'privatelink.openai.azure.com', 'privatelink.services.ai.azure.com')
    $monitorZones = @('privatelink.monitor.azure.com', 'privatelink.oms.opinsights.azure.com', 'privatelink.ods.opinsights.azure.com', 'privatelink.agentsvc.azure-automation.net', 'privatelink.blob.core.windows.net')
    $targets = @{
        blob = @($storageId, 'blob', @('privatelink.blob.core.windows.net'))
        models = @($modelsId, 'account', $cognitiveZones)
        agents = @($agentsId, 'account', $cognitiveZones)
        registry = @($registryId, 'registry', @('privatelink.azurecr.io'))
        monitor = @($lab.ampls.id, 'azuremonitor', $monitorZones)
    }
    foreach ($zone in @($cognitiveZones + $monitorZones + 'privatelink.azurecr.io' | Sort-Object -Unique)) {
        $lab.zones[$zone] = Add-LabResource api2026_dns_zone $zone 'Microsoft.Network/privateDnsZones@2020-06-01' $group @{
            properties = @{}
        } -Id "$group/providers/Microsoft.Network/privateDnsZones/$zone"
        $null = Add-LabResource api2026_dns_link $zone 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' $lab.zones[$zone].id @{
            properties = @{ registrationEnabled = $false; virtualNetwork = @{ id = $lab.vnet.id } }
        } -Id "$($lab.zones[$zone].id)/virtualNetworkLinks/lab"
    }
    foreach ($key in $targets.Keys) {
        $target = $targets[$key]
        $lab.endpoints[$key] = Add-LabResource api2026_private_endpoint $key 'Microsoft.Network/privateEndpoints@2024-05-01' $group @{
            properties = @{
                subnet = @{ id = $lab.subnets['private-endpoints'].id }
                privateLinkServiceConnections = @(@{ name = $key; properties = @{ privateLinkServiceId = $target[0]; groupIds = @($target[1]) } })
            }
        }
        $null = Add-LabResource api2026_dns_group $key 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' $lab.endpoints[$key].id @{
            properties = @{ privateDnsZoneConfigs = @($target[2] | ForEach-Object {
                @{ name = $_.Replace('.', '-'); properties = @{ privateDnsZoneId = $lab.zones[$_].id } }
            }) }
        } -Id "$($lab.endpoints[$key].id)/privateDnsZoneGroups/default"
    }
    foreach ($key in @('positive', 'negative')) {
        $lab.identities[$key] = Add-LabResource api2026_identity $key 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' $group @{}
        $identity = $lab.identities[$key].output.properties
        Assert-Guid $identity.principalId
        Assert-Guid $identity.clientId
        Assert-ConfiguredValue $identity.tenantId $tenant 'private-client identity tenant'
    }
    if ($lab.identities.positive.output.properties.principalId -ieq $lab.identities.negative.output.properties.principalId -or
        $lab.identities.positive.output.properties.clientId -ieq $lab.identities.negative.output.properties.clientId) {
        Stop-Api2026 'Positive and negative clients require distinct fresh identities.'
    }
    $lab.nic = Add-LabResource api2026_nic client 'Microsoft.Network/networkInterfaces@2024-05-01' $group @{
        properties = @{
            enableAcceleratedNetworking = $true; enableIPForwarding = $false
            ipConfigurations = @(@{ name = 'private'; properties = @{
                primary = $true; privateIPAddressVersion = 'IPv4'; privateIPAllocationMethod = 'Static'
                privateIPAddress = '10.244.2.4'; subnet = @{ id = $lab.subnets['verification-client'].id }
            } })
        }
    }
    $vm = Get-StateValue api2026_vm client
    $diskName = $vm.body.properties.storageProfile.osDisk.name
    Assert-Name $diskName
    $ssh = $vm.body.properties.osProfile.linuxConfiguration.ssh.publicKeys
    if ($ssh -isnot [array] -or $ssh.Count -ne 1 -or
        $ssh[0].keyData -isnot [string] -or $ssh[0].keyData -cnotmatch '^(ssh-ed25519|ssh-rsa) [A-Za-z0-9+/]{64,}={0,3}( [^\r\n]*)?$') {
        Stop-Api2026 'Verification VM requires one supplied OpenSSH public key, not password or private material.'
    }
    $lab.vm = Add-LabResource api2026_vm client 'Microsoft.Compute/virtualMachines@2024-07-01' $group @{
        properties = @{
            hardwareProfile = @{ vmSize = 'Standard_D2s_v5' }
            storageProfile = @{
                imageReference = @{ publisher = 'Canonical'; offer = 'ubuntu-24_04-lts'; sku = 'server'; version = '24.04.202610210' }
                osDisk = @{ name = $diskName; createOption = 'FromImage'; deleteOption = 'Detach'; caching = 'ReadWrite'; managedDisk = @{ storageAccountType = 'Premium_LRS' } }
            }
            osProfile = @{
                computerName = $vm.name; adminUsername = 'aigwverify'; allowExtensionOperations = $true
                linuxConfiguration = @{ disablePasswordAuthentication = $true; provisionVMAgent = $true
                    ssh = @{ publicKeys = @(@{ path = '/home/aigwverify/.ssh/authorized_keys'; keyData = $ssh[0].keyData }) }
                }
            }
            networkProfile = @{ networkInterfaces = @(@{ id = $lab.nic.id; properties = @{ primary = $true; deleteOption = 'Detach' } }) }
            securityProfile = @{ securityType = 'TrustedLaunch'; uefiSettings = @{ secureBootEnabled = $true; vTpmEnabled = $true } }
            diagnosticsProfile = @{ bootDiagnostics = @{ enabled = $false } }
        }
    }
    Assert-Guid $vm.identity[0].principal_id
    Assert-ConfiguredValue $vm.identity[0].tenant_id $tenant 'verification VM tenant'
    if ($vm.identity.Count -ne 1 -or $vm.identity[0].type -cne 'SystemAssigned, UserAssigned' -or
        $vm.identity[0].identity_ids.Count -ne 2 -or
        @(Compare-Object @($lab.identities.Values.id) @($vm.identity[0].identity_ids)).Count) {
        Stop-Api2026 'Verification VM must attach exactly the two owned test identities.'
    }
    $lab.disk = Add-LabResource disk_access client 'Microsoft.Compute/disks@2024-03-02' $group @{
        properties = @{ networkAccessPolicy = 'DenyAll'; publicNetworkAccess = 'Disabled' }
    } -Id "$group/providers/Microsoft.Compute/disks/$diskName" -TerraformType azapi_update_resource
    Assert-ConfiguredValue $vm.output.properties.storageProfile.osDisk.managedDisk.id $lab.disk.resource_id 'verification VM tracked native OS disk'
    $lab.container = Add-LabResource api2026_container lab 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' "$storageId/blobServices/default" @{
        properties = @{ publicAccess = 'None'; metadata = @{ purpose = 'bounded-private-verification' } }
    } -Id "$storageId/blobServices/default/containers/private-verification"
    $grants = @{
        models = @($modelsId, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
        project = @($projectId, 'a97b65f3-24c7-4388-baec-2e87135dc908')
        blob = @($lab.container.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
        registry = @($registryId, '8311e382-0749-4cb8-b61a-304f252e45ec')
        gateway = @($gatewayId, 'a6b68e3d-a1f0-4c60-8678-237c050cf4ea')
    }
    foreach ($key in @('gateway', 'agents')) {
        $grants["$key-query"] = @((Get-StateValue logs $key).id, '73c42c96-874c-492b-b04d-ab87d138a893')
        $grants["$key-monitor-read"] = @($insightsIds[$key], '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
        $grants["$key-monitor-publish"] = @($insightsIds[$key], '3913510d-42f4-4e42-8a64-420c390055eb')
    }
    foreach ($key in $grants.Keys) {
        $grant = Get-StateValue api2026_client_grant $key
        Assert-Guid $grant.name
        $null = Add-LabResource api2026_client_grant $key 'Microsoft.Authorization/roleAssignments@2022-04-01' $grants[$key][0] @{
            properties = @{
                principalId = $lab.identities.positive.output.properties.principalId; principalType = 'ServicePrincipal'
                roleDefinitionId = "$prefix/providers/Microsoft.Authorization/roleDefinitions/$($grants[$key][1])"
            }
        } -Id "$($grants[$key][0])/providers/Microsoft.Authorization/roleAssignments/$($grant.name)"
    }
    foreach ($resource in $stateByAddress.Values | Where-Object { $_.values.type -ceq 'Microsoft.Authorization/roleAssignments@2022-04-01' }) {
        if ($resource.values.body.properties.principalId -ieq $lab.identities.negative.output.properties.principalId) {
            Stop-Api2026 'The negative test identity must have no configured grant.'
        }
    }
    $lab.diagnostics = Add-LabResource api2026_blob_read_diagnostics lab 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' "$storageId/blobServices/default" @{
        properties = @{
            workspaceId = (Get-StateValue logs gateway).id; logAnalyticsDestinationType = 'Dedicated'
            logs = @('StorageRead', 'StorageWrite', 'StorageDelete' | ForEach-Object {
                @{ category = $_; categoryGroup = $null; enabled = $_ -ceq 'StorageRead'; retentionPolicy = @{ enabled = $false; days = 0 } }
            })
            metrics = @('Capacity', 'Transaction' | ForEach-Object {
                @{ category = $_; enabled = $false; retentionPolicy = @{ enabled = $false; days = 0 } }
            })
        }
    } -Id "$storageId/blobServices/default/providers/Microsoft.Insights/diagnosticSettings/blob-read"
    Assert-ConfiguredValue (Get-StateValue storage).body.properties @{
        allowBlobPublicAccess = $false; allowSharedKeyAccess = $false; publicNetworkAccess = 'Disabled'
        networkAcls = @{ bypass = 'None'; defaultAction = 'Deny'; resourceAccessRules = @(); virtualNetworkRules = @() }
    } 'fresh private Storage controls'
    if ((Get-StateValue storage).ignore_body_changes) { Stop-Api2026 'Fresh private Storage must not hide a historical policy overlay.' }
    $metadata = @{
        vnet_id = $lab.vnet.id; subnet_ids = @{}; private_endpoints = @{}; dns_zones = @{}; ampls_id = $lab.ampls.id
        client_vm_id = $lab.vm.id; client_private_ip = '10.244.2.4'; os_disk_id = $lab.disk.resource_id; identities = @{}
        container_id = $lab.container.id; storage_read_diagnostic_id = $lab.diagnostics.id
    }
    foreach ($key in $lab.subnets.Keys) { $metadata.subnet_ids[$key] = $lab.subnets[$key].id }
    foreach ($key in $lab.endpoints.Keys) { $metadata.private_endpoints[$key] = $lab.endpoints[$key].id }
    foreach ($key in $lab.zones.Keys) { $metadata.dns_zones[$key] = $lab.zones[$key].id }
    foreach ($key in $lab.identities.Keys) {
        $identity = $lab.identities[$key]
        $metadata.identities[$key] = @{
            id = $identity.id; principal_id = $identity.output.properties.principalId
            client_id = $identity.output.properties.clientId; tenant_id = $identity.output.properties.tenantId
        }
    }
    Assert-ConfiguredValue (Get-Output api2026_private_lab) $metadata 'private-lab output bindings'
}

function Test-ExternalPrivateEndpointNsg {
    $nsg = Invoke-AzureJson @('rest', '--method', 'get', '--url',
        "https://management.azure.com${ExpectedPrivateEndpointSubnetNsgId}?api-version=2024-05-01")
    Assert-ConfiguredValue $nsg @{
        id = $ExpectedPrivateEndpointSubnetNsgId; type = 'Microsoft.Network/networkSecurityGroups'
        location = $gatewayState.location
        properties = @{
            provisioningState = 'Succeeded'; securityRules = @()
            subnets = @(@{ id = $lab.subnets['private-endpoints'].id })
        }
    } 'explicit external private-endpoint NSG'
    if ($nsg.properties.networkInterfaces) { Stop-Api2026 'External private-endpoint NSG must not attach to an interface.' }
    $expectedRules = @(
        foreach ($rule in @(
            @('AllowVnetInBound', 'Inbound', 'Allow', 65000, 'VirtualNetwork', 'VirtualNetwork'),
            @('AllowAzureLoadBalancerInBound', 'Inbound', 'Allow', 65001, 'AzureLoadBalancer', '*'),
            @('DenyAllInBound', 'Inbound', 'Deny', 65500, '*', '*'),
            @('AllowVnetOutBound', 'Outbound', 'Allow', 65000, 'VirtualNetwork', 'VirtualNetwork'),
            @('AllowInternetOutBound', 'Outbound', 'Allow', 65001, '*', 'Internet'),
            @('DenyAllOutBound', 'Outbound', 'Deny', 65500, '*', '*')
        )) {
            @{
                name = $rule[0]
                properties = @{
                    direction = $rule[1]; access = $rule[2]; priority = $rule[3]
                    sourceAddressPrefix = $rule[4]; destinationAddressPrefix = $rule[5]
                    protocol = '*'; sourcePortRange = '*'; destinationPortRange = '*'
                }
            }
        }
    )
    if ($nsg.properties.defaultSecurityRules -isnot [array]) { Stop-Api2026 'Missing external NSG default rule array.' }
    Assert-ConfiguredValue @($nsg.properties.defaultSecurityRules | Sort-Object name) @($expectedRules | Sort-Object name) 'external NSG default rules'
    foreach ($rule in $nsg.properties.defaultSecurityRules) {
        foreach ($field in @('sourceAddressPrefixes', 'destinationAddressPrefixes', 'sourcePortRanges', 'destinationPortRanges',
            'sourceApplicationSecurityGroups', 'destinationApplicationSecurityGroups')) {
            if ($rule.properties[$field]) { Stop-Api2026 'Unexpected extended default NSG rule selector.' }
        }
    }
    @{
        id = $ExpectedPrivateEndpointSubnetNsgId; status = 'VERIFIED'; customRules = 0; defaultRules = 6
        ownership = 'External; origin not established. Not imported or modified.'
        privateEndpointNetworkPolicies = 'Disabled'
    }
}

function Test-Api2026PrivateLab {
    $ready = @('api2026_vnet', 'api2026_nsg', 'api2026_nat_ip', 'api2026_nat', 'api2026_subnet', 'api2026_ampls',
        'api2026_private_endpoint', 'api2026_dns_zone', 'api2026_dns_group', 'api2026_dns_link', 'api2026_nic', 'api2026_vm', 'disk_access')
    foreach ($address in $labResources.Keys) {
        $entry = $labResources[$address]
        $resource = Read-Resource $entry.name $entry.key -TerraformType $entry.terraformType -Ready:($entry.name -in $ready)
        Assert-LabBody $entry.name $entry.key $resource $entry.body -Live
        if ($entry.name -ceq 'api2026_client_grant') {
            Assert-ConfiguredValue $resource.properties.scope $expectedResources[$address].parent_id 'live private-client grant scope'
        }
        $externalNsg = if ($ExpectedPrivateEndpointSubnetNsgId) { Test-ExternalPrivateEndpointNsg } else { $null }
    }
    foreach ($key in @('positive', 'negative')) {
        $identity = $liveResources[(Get-Address api2026_identity $key)]
        Assert-ConfiguredValue $identity.properties $lab.identities[$key].output.properties 'live private-client identity'
    }
    $vm = $liveResources[(Get-Address api2026_vm client)]
    Assert-ConfiguredValue $vm.identity @{
        type = 'SystemAssigned, UserAssigned'; tenantId = $tenant; principalId = $lab.vm.identity[0].principal_id
    } 'live verification VM identity'
    Assert-Map $vm.identity.userAssignedIdentities 'live VM user-assigned identities'
    if (@(Compare-Object @($lab.identities.Values.id) @($vm.identity.userAssignedIdentities.Keys)).Count) {
        Stop-Api2026 'Live verification VM attaches a different test identity.'
    }
    foreach ($identity in $lab.identities.Values) {
        Assert-ConfiguredValue $vm.identity.userAssignedIdentities[$identity.id] @{
            principalId = $identity.output.properties.principalId; clientId = $identity.output.properties.clientId
        } 'live attached test identity'
    }
    Assert-ConfiguredValue $vm.properties.storageProfile.osDisk.managedDisk.id $lab.disk.resource_id 'live tracked OS disk'
    $disk = $liveResources[(Get-Address disk_access client azapi_update_resource)]
    Assert-ConfiguredValue $disk.managedBy $lab.vm.id 'native disk VM ownership'
    $nicIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $lab.endpoints.Keys) {
        $endpoint = $liveResources[(Get-Address api2026_private_endpoint $key)]
        Assert-ConfiguredValue $endpoint.properties.privateLinkServiceConnections[0].properties.privateLinkServiceConnectionState.status 'Approved' 'private endpoint approval'
        if ($endpoint.properties.networkInterfaces -isnot [array] -or $endpoint.properties.networkInterfaces.Count -ne 1) {
            Stop-Api2026 'Expected one RP-owned interface for each baseline private endpoint.'
        }
        $id = $endpoint.properties.networkInterfaces[0].id
        Assert-AllowedId $id
        if ($id -notmatch ('^' + [regex]::Escape($groupIds.gateway) + '/providers/Microsoft.Network/networkInterfaces/[a-zA-Z0-9_.-]+$') -or
            $id -ieq $lab.nic.id -or -not $nicIds.Add($id)) {
            Stop-Api2026 'Unexpected or shared RP-owned private endpoint interface.'
        }
        $nic = Invoke-AzureJson @('rest', '--method', 'get', '--url', "https://management.azure.com${id}?api-version=2024-05-01")
        Assert-ConfiguredValue $nic @{
            id = $id; type = 'Microsoft.Network/networkInterfaces'
            properties = @{ provisioningState = 'Succeeded'; privateEndpoint = @{ id = $endpoint.id }; enableIPForwarding = $false }
        } 'RP-owned private endpoint interface'
        if ($nic.properties.ipConfigurations -isnot [array] -or -not $nic.properties.ipConfigurations.Count) {
            Stop-Api2026 'Private endpoint interface has no private addresses.'
        }
        foreach ($ip in $nic.properties.ipConfigurations) {
            $parsed = $null
            if ($ip.properties.publicIPAddress -or -not [Net.IPAddress]::TryParse($ip.properties.privateIPAddress, [ref]$parsed) -or
                $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
                ($parsed.GetAddressBytes()[0..2] -join '.') -cne '10.244.1' -or $parsed.GetAddressBytes()[3] -in @(0, 255)) {
                Stop-Api2026 'Private endpoint interface is not private within the owned PE subnet.'
            }
            Assert-ConfiguredValue $ip.properties.subnet.id $lab.subnets['private-endpoints'].id 'PE interface subnet'
        }
    }
    @{
        managedResources = $labResources.Count; privateEndpoints = $lab.endpoints.Count; dnsZones = $lab.zones.Count
        scopedMonitorResources = 4; positiveClientGrants = 11; negativeConfiguredGrants = 0
        nativeDiskRestriction = 'Tracked and read back'; rpOwnedInterfaces = $nicIds.Count
        gatewayIngress = 'NOT IMPLEMENTED'; privateTrafficAndDnsResolution = 'NOT TESTED'
        telemetryAndStorageReadDelivery = 'NOT TESTED'; negativeIdentityEffectiveAccess = 'NOT TESTED'
        externalPrivateEndpointNsg = $externalNsg
        scope = 'Exact owned configuration and five referenced RP-owned NICs, not an exhaustive RG or inherited-access audit.'
    }
}
