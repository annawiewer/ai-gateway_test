#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$entry = Join-Path $root 'api2026gateway'
$checker = Join-Path $root 'scripts\Test-Api2026Deployment.ps1'
$probe = Join-Path $root 'scripts\Test-ModelAliases.ps1'
$profile = Get-Content -LiteralPath (Join-Path $entry 'model-profile.json') -Raw | ConvertFrom-Json -AsHashtable
$subscription = '00000000-0000-0000-0000-000000000001'
$tenant = '00000000-0000-0000-0000-000000000002'
$gatewayPrincipal = '00000000-0000-0000-0000-00000000000a'
$projectPrincipal = '00000000-0000-0000-0000-000000000004'
$prefix = "/subscriptions/$subscription"
$fixtureDirectory = Join-Path '.' ".api2026-fixture-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $fixtureDirectory
$caseCount = 0

function Copy-Json($Value) { $Value | ConvertTo-Json -Depth 80 | ConvertFrom-Json -AsHashtable -Depth 80 }

function Set-FixtureLayout([switch]$SingleGroup) {
    $script:groups = if ($SingleGroup) {
        @{ gateway = 'synthetic-single'; models = 'synthetic-single'; agents = 'synthetic-single' }
    }
    else { @{ gateway = 'synthetic-gateway'; models = 'synthetic-models'; agents = 'synthetic-agents' } }
    $script:groupIds = @{}
    foreach ($key in $groups.Keys) { $script:groupIds[$key] = "$prefix/resourceGroups/$($groups[$key])" }
    $script:gatewayId = "$($groupIds.gateway)/providers/Microsoft.ApiManagement/aigateways/fixture"
    $script:modelsId = "$($groupIds.models)/providers/Microsoft.CognitiveServices/accounts/models"
    $script:safetyCollectionId = "$modelsId/raiPolicies"
    $script:safetyPolicyId = "$modelsId/raiPolicies/Microsoft.DefaultV2"
    $script:agentsId = "$($groupIds.agents)/providers/Microsoft.CognitiveServices/accounts/agents"
    $script:projectId = "$agentsId/projects/project"
    $script:storageId = "$($groupIds.agents)/providers/Microsoft.Storage/storageAccounts/syntheticstorage"
    $script:registryId = "$($groupIds.agents)/providers/Microsoft.ContainerRegistry/registries/syntheticregistry"
    $script:workspace = "$gatewayId/workspaces/default"
    $script:providerId = "$workspace/modelProviders/foundry"
    $script:keyId = "$gatewayId/apiKeys/default"
}

function Add-FixtureResource([string]$Name, [string]$Key, [string]$Type, [string]$Id, [string]$Parent, [hashtable]$Body, [string]$TerraformType = 'azapi_resource') {
    $address = "module.gateway.$TerraformType.$Name"
    if ($Key) { $address += '["' + $Key + '"]' }
    $value = @{ id = $Id; name = $Id.Split('/')[-1]; parent_id = $Parent; type = $Type; body = $Body }
    if ($TerraformType -ceq 'azapi_update_resource') {
        $value.Remove('name'); $value.Remove('parent_id'); $value.resource_id = $Id
    }
    $resource = @{ mode = 'managed'; type = $TerraformType; address = $address; values = $value }
    $global:api2026Fixture.resources.Add($resource)
    $global:api2026Fixture.state[$address] = $value
    $live = Copy-Json $Body
    $live.id = $Id
    $live.type = $Type.Split('@')[0]
    if (-not $live.Contains('properties')) { $live.properties = @{} }
    $live.properties.provisioningState = 'Succeeded'
    if ($Name -in @('resource_group', 'gateway', 'models', 'agents', 'project', 'storage', 'registry', 'logs', 'insights',
        'api2026_vnet', 'api2026_nsg', 'api2026_nat_ip', 'api2026_nat', 'api2026_ampls', 'api2026_private_endpoint',
        'api2026_dns_zone', 'api2026_dns_link', 'api2026_identity', 'api2026_nic', 'api2026_vm')) {
        $value.location = if ($Name -in @('api2026_ampls', 'api2026_dns_zone', 'api2026_dns_link')) { 'global' } else { 'swedencentral' }
        $live.location = $value.location
    }
    $global:api2026Fixture.arm[$Id] = $live
    $global:api2026Fixture.versions[$Id] = $Type.Split('@')[1]
    $value
}

function Add-FixtureRole([string]$Key, [string]$Scope, [string]$Principal, [string]$PrincipalType, [string]$RoleId, [string]$ResourceName = 'role_assignment') {
    $name = [guid]::NewGuid().ToString()
    $id = "$Scope/providers/Microsoft.Authorization/roleAssignments/$name"
    $null = Add-FixtureResource $ResourceName $Key 'Microsoft.Authorization/roleAssignments@2022-04-01' $id $Scope @{
        properties = @{ principalId = $Principal; principalType = $PrincipalType; roleDefinitionId = "$prefix/providers/Microsoft.Authorization/roleDefinitions/$RoleId" }
    }
    $global:api2026Fixture.arm[$id].properties.scope = $Scope
    $id
}

function Reset-Fixture {
    param([string[]]$AllowedClientCidrs = @(), [switch]$SingleGroup, [switch]$PrivateLab)
    $script:caseCount++
    Set-FixtureLayout -SingleGroup:($SingleGroup -or $PrivateLab)
    $profile = Copy-Json $script:profile
    $global:api2026Fixture = @{
        resources = [Collections.Generic.List[object]]::new()
        state = @{}
        arm = @{}
        versions = @{}
        safetyPages = @{}
        missingResources = @()
        armCalls = 0
        accountCalls = 0
        credentialCalls = 0
        httpCalls = 0
        authentication = 'ApiKey'
        account = @{ id = $subscription; tenantId = $tenant }
        secret = @{ properties = @{ primaryValue = 'synthetic-key-do-not-persist' } }
        token = 'synthetic-token-do-not-persist'
        credentialExit = 0
        negativeStatus = 401
        negativeMessage = 'Invalid authentication token.'
        positiveStatus = 200
        completionTokens = 2
        transportFailure = $false
        keyUrl = $null
        requestedAliases = [Collections.Generic.List[string]]::new()
        expectedRoot = $script:entry
        expectedSubscription = $script:subscription
        expectedKeyId = $script:keyId
        extraArguments = @{}
    }
    $f = $global:api2026Fixture
    $groupKeys = if ($SingleGroup -or $PrivateLab) { @('gateway') } else { @('gateway', 'models', 'agents') }
    foreach ($key in $groupKeys) { $null = Add-FixtureResource resource_group $key 'Microsoft.Resources/resourceGroups@2021-04-01' $groupIds[$key] $prefix @{ properties = @{} } }
    $gateway = Add-FixtureResource gateway '' 'Microsoft.ApiManagement/aigateways@2026-09-01-preview' $gatewayId $groupIds.gateway @{ properties = @{} }
    $gateway.identity = @(@{ principal_id = $gatewayPrincipal; tenant_id = $tenant; type = 'SystemAssigned' })
    $f.arm[$gatewayId].identity = @{ principalId = $gatewayPrincipal; tenantId = $tenant; type = 'SystemAssigned' }
    $f.arm[$gatewayId].properties.frontend = @{ defaultHostname = 'gateway.example' }
    foreach ($key in @('models', 'agents')) {
        $id = if ($key -eq 'models') { $modelsId } else { $agentsId }
        $null = Add-FixtureResource $key '' 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' $id $groupIds[$key] @{
            kind = 'AIServices'; sku = @{ name = 'S0' }
            properties = @{ allowProjectManagement = $true; customSubDomainName = $key; disableLocalAuth = $true; publicNetworkAccess = 'Enabled'; networkAcls = @{ defaultAction = 'Allow'; virtualNetworkRules = @(); ipRules = @() } }
        }
    }
    $f.arm[$modelsId].properties.endpoint = 'https://models.example/'
    $project = Add-FixtureResource project '' 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' $projectId $agentsId @{
        properties = @{ displayName = 'Synthetic project'; description = 'Fixture only' }
    }
    $project.identity = @(@{ principal_id = $projectPrincipal; tenant_id = $tenant; type = 'SystemAssigned' })
    $f.arm[$projectId].identity = @{ principalId = $projectPrincipal; tenantId = $tenant; type = 'SystemAssigned' }
    $null = Add-FixtureResource storage '' 'Microsoft.Storage/storageAccounts@2024-01-01' $storageId $groupIds.agents @{
        kind = 'StorageV2'; sku = @{ name = 'Standard_LRS' }
        properties = @{ minimumTlsVersion = 'TLS1_2'; allowBlobPublicAccess = $false; allowSharedKeyAccess = $false; publicNetworkAccess = 'Enabled'; networkAcls = @{ bypass = 'AzureServices'; defaultAction = 'Allow'; virtualNetworkRules = @() } }
    }
    $f.arm[$storageId].properties.primaryEndpoints = @{ blob = 'https://syntheticstorage.blob.core.windows.net/' }
    $null = Add-FixtureResource registry '' 'Microsoft.ContainerRegistry/registries@2023-07-01' $registryId $groupIds.agents @{
        sku = @{ name = 'Premium' }; properties = @{ adminUserEnabled = $false; publicNetworkAccess = 'Enabled'; zoneRedundancy = 'Disabled' }
    }
    $f.arm[$registryId].properties.loginServer = 'syntheticregistry.azurecr.io'
    $insightsIds = @{}
    $logIds = @{}
    foreach ($key in @('gateway', 'agents')) {
        $logIds[$key] = "$($groupIds[$key])/providers/Microsoft.OperationalInsights/workspaces/$key-logs"
        $insightsIds[$key] = "$($groupIds[$key])/providers/Microsoft.Insights/components/$key-insights"
        $null = Add-FixtureResource logs $key 'Microsoft.OperationalInsights/workspaces@2023-09-01' $logIds[$key] $groupIds[$key] @{
            properties = @{ retentionInDays = 30; features = @{ enableLogAccessUsingOnlyResourcePermissions = $true }; sku = @{ name = 'PerGB2018' } }
        }
        $null = Add-FixtureResource insights $key 'Microsoft.Insights/components@2020-02-02' $insightsIds[$key] $groupIds[$key] @{
            kind = 'web'; properties = @{ Application_Type = 'web'; IngestionMode = 'LogAnalytics'; WorkspaceResourceId = $logIds[$key] }
        }
        $f.arm[$insightsIds[$key]].properties.ConnectionString = "synthetic-$key-connection-do-not-persist"
    }
    $null = Add-FixtureResource foundry_provider '' 'Microsoft.ApiManagement/aigateways/workspaces/modelProviders@2026-09-01-preview' $providerId $workspace @{
        properties = @{
            kind = 'Foundry'; displayName = 'Foundry'
            foundry = @{ endpoint = 'https://models.example/'; resourceIds = @($modelsId); authentication = @{ kind = 'ManagedIdentity'; managedIdentity = @{ resource = 'https://cognitiveservices.azure.com/' } } }
        }
    }
    $deploymentIds = @{}
    $modelApis = @{}
    foreach ($key in $profile.model_deployments.Keys) {
        $model = $profile.model_deployments[$key]
        $deploymentIds[$key] = "$modelsId/deployments/$key"
        $modelApis[$key] = @{ api_format = $model.api_format; endpoints = $model.endpoints }
        $null = Add-FixtureResource model_deployment $key 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' $deploymentIds[$key] $modelsId @{
            sku = @{ name = $model.sku_name; capacity = $model.capacity }
            properties = @{ model = @{ name = $model.model_name; version = $model.model_version; format = $model.model_format }; raiPolicyName = 'Microsoft.DefaultV2' }
        }
        $policies = @(
            @{ type = 'tokenLimit'; period = 'minute'; count = $model.token_limit; counterKey = @('identity') },
            @{ id = 'monthly-caller-budget'; type = 'costLimit'; period = 'month'; amount = $model.cost_limit; counterKey = @('identity') },
            @{ type = 'requestRateLimit'; callsPerPeriod = $model.request_limit; periodSeconds = 60; counterKey = @('identity') }
        )
        if ($AllowedClientCidrs.Count) { $policies += @{ type = 'ipFilter'; action = 'Allow'; cidrRanges = @($AllowedClientCidrs | Sort-Object -Unique) } }
        $null = Add-FixtureResource catalog_model $key 'Microsoft.ApiManagement/aigateways/workspaces/modelProviders/models@2026-09-01-preview' "$providerId/models/$key" $providerId @{
            properties = @{
                description = $model.description; displayName = $model.model_name; apiFormat = $model.api_format; supportedEndpoints = $model.endpoints
                deployment = @{ resourceId = $deploymentIds[$key]; modelName = $key; modelVersion = $model.model_version }
                policies = $policies
            }
        }
        $f.arm["$providerId/models/$key"].properties.providerKind = 'Foundry'
    }
    $filters = @(
        foreach ($category in @('Hate', 'Sexual', 'Violence', 'Selfharm')) {
            foreach ($source in @('Prompt', 'Completion')) {
                @{ name = $category; source = $source; enabled = $true; blocking = $true; severityThreshold = 'Medium' }
            }
        }
        @{ name = 'Jailbreak'; source = 'Prompt'; enabled = $true; blocking = $true }
        @{ name = 'Protected Material Text'; source = 'Completion'; enabled = $true; blocking = $true }
        @{ name = 'Protected Material Code'; source = 'Completion'; enabled = $true; blocking = $false }
        @{ name = 'Indirect Attack'; source = 'Prompt'; enabled = $true; blocking = $false }
    )
    $f.arm[$safetyPolicyId] = @{
        id = $safetyPolicyId; type = 'Microsoft.CognitiveServices/accounts/raiPolicies'
        properties = @{ type = 'SystemManaged'; mode = 'Blocking'; contentFilters = $filters }
    }
    $f.versions[$safetyPolicyId] = '2025-04-01-preview'
    $f.arm[$safetyCollectionId] = @{ value = @($f.arm[$safetyPolicyId]) }
    $f.versions[$safetyCollectionId] = '2025-04-01-preview'
    $aliases = @{}
    foreach ($key in $profile.model_aliases.Keys) {
        $alias = $profile.model_aliases[$key]
        $aliases[$key] = @{ alias_name = $alias.alias_name; api_format = 'OpenAIChatCompletions'; endpoints = @('/openai/v1/chat/completions', '/openai/v1/responses'); backend_models = $alias.backend_models }
        $null = Add-FixtureResource model_alias $key 'Microsoft.ApiManagement/aigateways/workspaces/aliases@2026-09-01-preview' "$workspace/aliases/$key" $workspace @{
            properties = @{
                aliasName = $alias.alias_name; description = $alias.description
                backendModels = @($alias.backend_models | ForEach-Object { @{ resourceId = "$providerId/models/$($_.deployment)"; priority = $_.priority; weight = $_.weight } })
            }
        }
    }
    $null = Add-FixtureResource runtime_api_key '' 'Microsoft.ApiManagement/aigateways/apiKeys@2026-09-01-preview' $keyId $gatewayId @{ properties = @{ displayName = 'All APIs subscription' } }
    $null = Add-FixtureResource telemetry_exporter '' 'Microsoft.ApiManagement/aigateways/workspaces/telemetryExporters@2025-09-01-preview' "$workspace/telemetryExporters/appinsights" $workspace @{
        properties = @{ kind = 'ApplicationInsights'; payloadCapture = $false; applicationInsights = @{ resourceId = $insightsIds.gateway; connectionString = $f.arm[$insightsIds.gateway].properties.ConnectionString } }
    }
    $null = Add-FixtureResource mcp_tool_server 'microsoft-learn' 'Microsoft.ApiManagement/aigateways/workspaces/toolServers@2025-09-01-preview' "$workspace/toolServers/microsoft-learn" $workspace @{
        properties = @{
            displayName = 'Microsoft Learn'; description = 'Microsoft Learn'; type = 'mcp'
            endpoints = @(@{ namespace = 'microsoft-learn'; kind = 'mcp'; mcp = @{ url = 'https://learn.microsoft.com/api/mcp'; transport = 'streamableHttp' } })
            policies = @(@{ type = 'requestRateLimit'; callsPerPeriod = 20; periodSeconds = 60; counterKey = @('identity') })
        }
    }
    $null = Add-FixtureResource storage_connection '' 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' "$projectId/connections/syntheticstorage" $projectId @{
        properties = @{ category = 'AzureStorageAccount'; authType = 'AAD'; target = 'https://syntheticstorage.blob.core.windows.net/'; metadata = @{ ApiType = 'Azure'; ResourceId = $storageId; location = 'swedencentral' } }
    }
    $null = Add-FixtureResource registry_connection '' 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' "$projectId/connections/syntheticregistry-conn" $projectId @{
        properties = @{ category = 'ContainerRegistry'; authType = 'ManagedIdentity'; isSharedToAll = $false; target = 'syntheticregistry.azurecr.io'; metadata = @{ ResourceId = $registryId }; credentials = @{ clientId = $projectPrincipal; resourceId = $registryId } }
    }
    $null = Add-FixtureResource project_insights_connection agents 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' "$projectId/connections/agents-insights" $projectId @{
        properties = @{ category = 'AppInsights'; authType = 'ApiKey'; isSharedToAll = $false; target = $insightsIds.agents; metadata = @{ ApiType = 'Azure'; ResourceId = $insightsIds.agents; location = 'swedencentral' }; credentials = @{ key = $f.arm[$insightsIds.agents].properties.ConnectionString } }
    }
    $f.arm["$projectId/connections/agents-insights"].properties.isDefault = $false
    $f.defaultRoleId = Add-FixtureRole gateway-foundry-user $modelsId $gatewayPrincipal ServicePrincipal '53ca6127-db72-4b80-b1b0-d745d6d5456d'
    $null = Add-FixtureRole project-storage $storageId $projectPrincipal ServicePrincipal 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    $null = Add-FixtureRole project-acr-pull $registryId $projectPrincipal ServicePrincipal '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    $null = Add-FixtureRole project-contributor $agentsId $projectPrincipal ServicePrincipal '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68'
    $null = Add-FixtureRole project-openai-user $agentsId $projectPrincipal ServicePrincipal '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    $null = Add-FixtureRole project-user $agentsId $projectPrincipal ServicePrincipal 'a97b65f3-24c7-4388-baec-2e87135dc908'
    $f.outputs = @{
        gateway_contract = @{ value = @{ name = '2026'; resource_type = 'Microsoft.ApiManagement/aigateways'; backend_subnet_id = $null } }
        gateway_api_versions = @{ value = @{ gateway = '2026-09-01-preview'; catalog = '2026-09-01-preview'; aliases = '2026-09-01-preview'; api_keys = '2026-09-01-preview'; telemetry = '2025-09-01-preview'; tool_servers = '2025-09-01-preview' } }
        mcp_tool_server_ids = @{ value = @{ 'microsoft-learn' = "$workspace/toolServers/microsoft-learn" } }
        resource_groups = @{ value = Copy-Json $groups }
        gateway_id = @{ value = $gatewayId }; gateway_endpoint = @{ value = 'https://gateway.example' }; gateway_api_key_id = @{ value = $keyId }
        foundry_models_id = @{ value = $modelsId }; project_id = @{ value = $projectId }
        project_endpoint = @{ value = 'https://agents.services.ai.azure.com/api/projects/project' }
        storage_account_name = @{ value = 'syntheticstorage' }; container_registry_endpoint = @{ value = 'syntheticregistry.azurecr.io' }
        application_insights_ids = @{ value = $insightsIds }
        gateway_monitoring = @{ value = @{ kind = 'applicationInsights'; insights_id = $insightsIds.gateway; log_analytics_id = $logIds.gateway } }
        model_deployment_ids = @{ value = $deploymentIds }; model_api_configuration = @{ value = $modelApis }; model_alias_configuration = @{ value = $aliases }
    }
    if ($SingleGroup -or $PrivateLab) {
        $f.extraArguments.SingleResourceGroup = $true
        $f.extraArguments.AllowedResourceGroups = @($groups.gateway)
        $f.outputs.gateway_contract.value.single_resource_group = $true
        $f.outputs.gateway_contract.value.private_lab = [bool]$PrivateLab
    }
    if ($PrivateLab) { Set-OwnedPrivateLabFixture }
}

function Set-ExistingGroupFixture {
    $f = $global:api2026Fixture
    $address = 'module.gateway.azapi_resource.resource_group["gateway"]'
    $f.resources.RemoveAt([Array]::IndexOf(@($f.resources | ForEach-Object { $_.address }), $address))
    $f.state.Remove($address)
    # A reused group is a Terraform data source, so the checker must not read it as a managed resource.
    $f.missingResources = @($groupIds.gateway)
    $f.outputs.gateway_contract.value.existing_resource_group = $true
    $f.extraArguments.ExistingResourceGroup = $true
}

function Set-OwnedPrivateLabFixture {
    Set-PrivateBackendFixture
    $f = $global:api2026Fixture
    $f.extraArguments.PrivateLab = $true
    $f.extraArguments.Remove('ExpectedBackendSubnetId')
    $group = $groupIds.gateway
    $vnetId = "$group/providers/Microsoft.Network/virtualNetworks/private-fixture"
    $amplsId = "$group/providers/Microsoft.Insights/privateLinkScopes/private-fixture"
    $natId = "$group/providers/Microsoft.Network/natGateways/egress"
    $pipId = "$group/providers/Microsoft.Network/publicIPAddresses/egress"
    $clientNicId = "$group/providers/Microsoft.Network/networkInterfaces/verification"
    $vmId = "$group/providers/Microsoft.Compute/virtualMachines/verification"
    $diskId = "$group/providers/Microsoft.Compute/disks/os-verification"
    $containerId = "$storageId/blobServices/default/containers/private-verification"
    $diagnosticId = "$storageId/blobServices/default/providers/Microsoft.Insights/diagnosticSettings/blob-read"
    $metadata = @{
        vnet_id = $vnetId; ampls_id = $amplsId; client_vm_id = $vmId; client_private_ip = '10.244.2.4'
        os_disk_id = $diskId; container_id = $containerId; storage_read_diagnostic_id = $diagnosticId
        subnet_ids = @{}; private_endpoints = @{}; dns_zones = @{}; identities = @{}
    }
    foreach ($key in @('gateway-outbound', 'private-endpoints', 'verification-client')) { $metadata.subnet_ids[$key] = "$vnetId/subnets/$key" }
    $f.outputs.gateway_contract.value.backend_subnet_id = $metadata.subnet_ids['gateway-outbound']
    $f.state['module.gateway.azapi_resource.gateway'].body.properties.backend.subnet.id = $metadata.subnet_ids['gateway-outbound']
    $f.arm[$gatewayId].properties.backend.subnet.id = $metadata.subnet_ids['gateway-outbound']
    $storage = $f.state['module.gateway.azapi_resource.storage']
    $storage.body.properties.networkAcls.bypass = 'None'
    $storage.body.properties.networkAcls.resourceAccessRules = @()
    $storage.ignore_body_changes = @()
    $f.arm[$storageId].properties.networkAcls = Copy-Json $storage.body.properties.networkAcls
    $null = Add-FixtureResource api2026_vnet lab 'Microsoft.Network/virtualNetworks@2024-05-01' $vnetId $group @{
        properties = @{ addressSpace = @{ addressPrefixes = @('10.244.0.0/16') }; dhcpOptions = @{ dnsServers = @() } }
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
                priority = $rule[1]; protocol = $rule[2]; access = 'Allow'; direction = 'Outbound'
                sourceAddressPrefix = '*'; sourcePortRange = '*'; destinationAddressPrefix = $rule[3]; destinationPortRanges = $rule[4]
            } }
        }
        foreach ($direction in @('Inbound', 'Outbound')) {
            @{ name = "deny-other-$($direction.ToLowerInvariant())"; properties = @{
                priority = 4096; protocol = '*'; access = 'Deny'; direction = $direction
                sourceAddressPrefix = '*'; sourcePortRange = '*'; destinationAddressPrefix = '*'; destinationPortRange = '*'
            } }
        }
    )
    $nsgIds = @{}
    foreach ($key in @('client', 'gateway')) {
        $nsgIds[$key] = "$group/providers/Microsoft.Network/networkSecurityGroups/$key"
        $null = Add-FixtureResource api2026_nsg $key 'Microsoft.Network/networkSecurityGroups@2024-05-01' $nsgIds[$key] $group @{
            properties = @{ securityRules = @(if ($key -ceq 'client') { $rules }) }
        }
    }
    $f.arm[$nsgIds.client].properties.securityRules = @($f.arm[$nsgIds.client].properties.securityRules | Sort-Object -Property name -Descending)
    $null = Add-FixtureResource api2026_nat_ip client 'Microsoft.Network/publicIPAddresses@2024-05-01' $pipId $group @{
        sku = @{ name = 'Standard'; tier = 'Regional' }; properties = @{ publicIPAllocationMethod = 'Static'; publicIPAddressVersion = 'IPv4' }
    }
    $null = Add-FixtureResource api2026_nat client 'Microsoft.Network/natGateways@2024-05-01' $natId $group @{
        sku = @{ name = 'Standard' }; properties = @{ publicIpAddresses = @(@{ id = $pipId }); idleTimeoutInMinutes = 4 }
    }
    $subnetProperties = @{
        'gateway-outbound' = @{
            addressPrefix = '10.244.0.0/24'; networkSecurityGroup = @{ id = $nsgIds.gateway }
            delegations = @(@{ name = 'gateway-integration'; properties = @{ serviceName = 'Microsoft.App/environments' } })
        }
        'private-endpoints' = @{ addressPrefix = '10.244.1.0/24'; delegations = @(); privateEndpointNetworkPolicies = 'Disabled' }
        'verification-client' = @{
            addressPrefix = '10.244.2.0/24'; defaultOutboundAccess = $false
            networkSecurityGroup = @{ id = $nsgIds.client }; natGateway = @{ id = $natId }
        }
    }
    foreach ($key in $subnetProperties.Keys) {
        $null = Add-FixtureResource api2026_subnet $key 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' $metadata.subnet_ids[$key] $vnetId @{
            properties = $subnetProperties[$key]
        }
    }
    $null = Add-FixtureResource api2026_ampls lab 'Microsoft.Insights/privateLinkScopes@2021-09-01' $amplsId $group @{
        properties = @{ accessModeSettings = @{ ingestionAccessMode = 'PrivateOnly'; queryAccessMode = 'PrivateOnly'; exclusions = @() } }
    }
    foreach ($key in @('gateway', 'agents')) {
        foreach ($kind in @('logs', 'insights')) {
            $id = $f.state["module.gateway.azapi_resource.$kind[`"$key`"]"].id
            $null = Add-FixtureResource api2026_monitor_resource "$key-$kind" 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01' "$amplsId/scopedResources/$key-$kind" $amplsId @{
                properties = @{ linkedResourceId = $id }
            }
        }
    }
    $cognitiveZones = @('privatelink.cognitiveservices.azure.com', 'privatelink.openai.azure.com', 'privatelink.services.ai.azure.com')
    $monitorZones = @('privatelink.monitor.azure.com', 'privatelink.oms.opinsights.azure.com', 'privatelink.ods.opinsights.azure.com',
        'privatelink.agentsvc.azure-automation.net', 'privatelink.blob.core.windows.net')
    foreach ($zone in @($cognitiveZones + $monitorZones + 'privatelink.azurecr.io' | Sort-Object -Unique)) {
        $id = "$group/providers/Microsoft.Network/privateDnsZones/$zone"
        $metadata.dns_zones[$zone] = $id
        $null = Add-FixtureResource api2026_dns_zone $zone 'Microsoft.Network/privateDnsZones@2020-06-01' $id $group @{ properties = @{} }
        $null = Add-FixtureResource api2026_dns_link $zone 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' "$id/virtualNetworkLinks/lab" $id @{
            properties = @{ registrationEnabled = $false; virtualNetwork = @{ id = $vnetId } }
        }
    }
    $targets = @{
        blob = @($storageId, 'blob', @('privatelink.blob.core.windows.net'))
        models = @($modelsId, 'account', $cognitiveZones)
        agents = @($agentsId, 'account', $cognitiveZones)
        registry = @($registryId, 'registry', @('privatelink.azurecr.io'))
        monitor = @($amplsId, 'azuremonitor', $monitorZones)
    }
    $ip = 4
    foreach ($key in $targets.Keys) {
        $id = "$group/providers/Microsoft.Network/privateEndpoints/$key"
        $metadata.private_endpoints[$key] = $id
        $null = Add-FixtureResource api2026_private_endpoint $key 'Microsoft.Network/privateEndpoints@2024-05-01' $id $group @{
            properties = @{
                subnet = @{ id = $metadata.subnet_ids['private-endpoints'] }
                privateLinkServiceConnections = @(@{ name = $key; properties = @{ privateLinkServiceId = $targets[$key][0]; groupIds = @($targets[$key][1]) } })
            }
        }
        $f.arm[$id].properties.privateLinkServiceConnections[0].properties.privateLinkServiceConnectionState = @{ status = 'Approved' }
        $nicId = "$group/providers/Microsoft.Network/networkInterfaces/$key-pe"
        $f.arm[$id].properties.networkInterfaces = @(@{ id = $nicId })
        $f.arm[$nicId] = @{
            id = $nicId; type = 'Microsoft.Network/networkInterfaces'
            properties = @{
                provisioningState = 'Succeeded'; privateEndpoint = @{ id = $id }; enableIPForwarding = $false
                ipConfigurations = @(@{ properties = @{ privateIPAddress = "10.244.1.$ip"; subnet = @{ id = $metadata.subnet_ids['private-endpoints'] } } })
            }
        }
        $f.versions[$nicId] = '2024-05-01'
        $ip++
        $null = Add-FixtureResource api2026_dns_group $key 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' "$id/privateDnsZoneGroups/default" $id @{
            properties = @{ privateDnsZoneConfigs = @($targets[$key][2] | ForEach-Object {
                @{ name = $_.Replace('.', '-'); properties = @{ privateDnsZoneId = $metadata.dns_zones[$_] } }
            }) }
        }
    }
    $index = 1
    foreach ($key in @('positive', 'negative')) {
        $id = "$group/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$key"
        $value = Add-FixtureResource api2026_identity $key 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' $id $group @{}
        $properties = @{ principalId = "00000000-0000-0000-0000-00000000002$index"; clientId = "00000000-0000-0000-0000-00000000003$index"; tenantId = $tenant }
        $value.output = @{ properties = Copy-Json $properties }
        foreach ($field in $properties.Keys) { $f.arm[$id].properties[$field] = $properties[$field] }
        $metadata.identities[$key] = @{ id = $id; principal_id = $properties.principalId; client_id = $properties.clientId; tenant_id = $tenant }
        $index++
    }
    $null = Add-FixtureResource api2026_nic client 'Microsoft.Network/networkInterfaces@2024-05-01' $clientNicId $group @{
        properties = @{
            enableAcceleratedNetworking = $true; enableIPForwarding = $false
            ipConfigurations = @(@{ name = 'private'; properties = @{
                primary = $true; privateIPAddressVersion = 'IPv4'; privateIPAllocationMethod = 'Static'; privateIPAddress = '10.244.2.4'
                subnet = @{ id = $metadata.subnet_ids['verification-client'] }
            } })
        }
    }
    $vm = Add-FixtureResource api2026_vm client 'Microsoft.Compute/virtualMachines@2024-07-01' $vmId $group @{
        properties = @{
            hardwareProfile = @{ vmSize = 'Standard_D2s_v5' }
            storageProfile = @{
                imageReference = @{ publisher = 'Canonical'; offer = 'ubuntu-24_04-lts'; sku = 'server'; version = '24.04.202610210' }
                osDisk = @{ name = 'os-verification'; createOption = 'FromImage'; deleteOption = 'Detach'; caching = 'ReadWrite'; managedDisk = @{ storageAccountType = 'Premium_LRS' } }
            }
            osProfile = @{
                computerName = 'verification'; adminUsername = 'aigwverify'; allowExtensionOperations = $true
                linuxConfiguration = @{ disablePasswordAuthentication = $true; provisionVMAgent = $true
                    ssh = @{ publicKeys = @(@{ path = '/home/aigwverify/.ssh/authorized_keys'; keyData = "ssh-ed25519 $('A' * 68) synthetic-public-material" }) }
                }
            }
            networkProfile = @{ networkInterfaces = @(@{ id = $clientNicId; properties = @{ primary = $true; deleteOption = 'Detach' } }) }
            securityProfile = @{ securityType = 'TrustedLaunch'; uefiSettings = @{ secureBootEnabled = $true; vTpmEnabled = $true } }
            diagnosticsProfile = @{ bootDiagnostics = @{ enabled = $false } }
        }
    }
    $vm.identity = @(@{ type = 'SystemAssigned, UserAssigned'; principal_id = '00000000-0000-0000-0000-000000000041'; tenant_id = $tenant; identity_ids = @($metadata.identities.Values.id) })
    $vm.output = @{ properties = @{ storageProfile = @{ osDisk = @{ managedDisk = @{ id = $diskId } } } } }
    $f.arm[$vmId].properties.storageProfile.osDisk.managedDisk.id = $diskId
    $f.arm[$vmId].identity = @{ type = 'SystemAssigned, UserAssigned'; principalId = $vm.identity[0].principal_id; tenantId = $tenant; userAssignedIdentities = @{} }
    foreach ($identity in $metadata.identities.Values) {
        $f.arm[$vmId].identity.userAssignedIdentities[$identity.id] = @{ principalId = $identity.principal_id; clientId = $identity.client_id }
    }
    $null = Add-FixtureResource disk_access client 'Microsoft.Compute/disks@2024-03-02' $diskId $group @{
        properties = @{ networkAccessPolicy = 'DenyAll'; publicNetworkAccess = 'Disabled' }
    } -TerraformType azapi_update_resource
    $f.arm[$diskId].managedBy = $vmId
    $null = Add-FixtureResource api2026_container lab 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' $containerId "$storageId/blobServices/default" @{
        properties = @{ publicAccess = 'None'; metadata = @{ purpose = 'bounded-private-verification' } }
    }
    $grants = @{
        models = @($modelsId, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
        project = @($projectId, 'a97b65f3-24c7-4388-baec-2e87135dc908')
        blob = @($containerId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
        registry = @($registryId, '8311e382-0749-4cb8-b61a-304f252e45ec')
        gateway = @($gatewayId, 'a6b68e3d-a1f0-4c60-8678-237c050cf4ea')
    }
    foreach ($key in @('gateway', 'agents')) {
        $grants["$key-query"] = @($f.state["module.gateway.azapi_resource.logs[`"$key`"]"].id, '73c42c96-874c-492b-b04d-ab87d138a893')
        $grants["$key-monitor-read"] = @($f.outputs.application_insights_ids.value[$key], '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
        $grants["$key-monitor-publish"] = @($f.outputs.application_insights_ids.value[$key], '3913510d-42f4-4e42-8a64-420c390055eb')
    }
    foreach ($key in $grants.Keys) {
        $null = Add-FixtureRole $key $grants[$key][0] $metadata.identities.positive.principal_id ServicePrincipal $grants[$key][1] api2026_client_grant
    }
    $null = Add-FixtureResource api2026_blob_read_diagnostics lab 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' $diagnosticId "$storageId/blobServices/default" @{
        properties = @{
            workspaceId = $f.outputs.gateway_monitoring.value.log_analytics_id; logAnalyticsDestinationType = 'Dedicated'
            logs = @(
                @{ category = 'StorageRead'; categoryGroup = $null; enabled = $true; retentionPolicy = @{ enabled = $false; days = 0 } }
                @{ category = 'StorageWrite'; categoryGroup = $null; enabled = $false; retentionPolicy = @{ enabled = $false; days = 0 } }
                @{ category = 'StorageDelete'; categoryGroup = $null; enabled = $false; retentionPolicy = @{ enabled = $false; days = 0 } }
            )
            metrics = @(
                @{ category = 'Capacity'; enabled = $false; retentionPolicy = @{ enabled = $false; days = 0 } }
                @{ category = 'Transaction'; enabled = $false; retentionPolicy = @{ enabled = $false; days = 0 } }
            )
        }
    }
    $f.outputs.api2026_private_lab = @{ value = $metadata }
}

function terraform {
    $global:LASTEXITCODE = 0
    if ($args[0] -ne "-chdir=$($global:api2026Fixture.expectedRoot)" -or $args.Count -ne 3 -or $args[2] -ne '-json') { throw 'Fixture rejected unexpected Terraform context/arguments.' }
    if ($args[1] -eq 'output') { return ($global:api2026Fixture.outputs | ConvertTo-Json -Depth 80) }
    if ($args[1] -ne 'show') { throw 'Fixture permits output/show only; no plan, refresh or mutation.' }
    @{ values = @{ root_module = @{ child_modules = @(@{ address = 'module.gateway'; resources = @($global:api2026Fixture.resources.ToArray()) }) } } } | ConvertTo-Json -Depth 80
}

function az {
    $f = $global:api2026Fixture
    $global:LASTEXITCODE = 0
    $index = [Array]::IndexOf($args, '--subscription')
    if ($index -lt 0 -or $args[$index + 1] -ne $f.expectedSubscription) { throw 'Fixture requires every Azure command to select the approved subscription explicitly.' }
    if ($args[0] -eq 'account' -and $args[1] -eq 'show') {
        $f.accountCalls++
        return ($f.account | ConvertTo-Json)
    }
    if ($args[0] -eq 'account' -and $args[1] -eq 'get-access-token') {
        if ($args[[Array]::IndexOf($args, '--resource') + 1] -ne 'https://azure-api.net/aigateway') { throw 'Wrong token audience.' }
        $f.credentialCalls++
        $global:LASTEXITCODE = $f.credentialExit
        return $f.token
    }
    if ($args[0] -ne 'rest') { throw 'Fixture prohibits account changes, grants, VMs and all other Azure operations.' }
    $method = $args[[Array]::IndexOf($args, '--method') + 1]
    $url = $args[[Array]::IndexOf($args, '--url') + 1]
    if ($method -eq 'post') {
        if ($url -cne "https://management.azure.com$($f.expectedKeyId)/listSecrets?api-version=2026-09-01-preview" -or $f.authentication -eq 'EntraId') { throw 'Unexpected key read/fallback.' }
        $f.keyUrl = $url
        $f.credentialCalls++
        $global:LASTEXITCODE = $f.credentialExit
        return ($f.secret | ConvertTo-Json -Depth 10)
    }
    $uri = [uri]$url
    if ($method -ne 'get' -or $uri.GetLeftPart([UriPartial]::Authority) -cne 'https://management.azure.com' -or
        -not $f.arm.ContainsKey($uri.AbsolutePath) -or
        ($uri.Query -cne "?api-version=$($f.versions[$uri.AbsolutePath])" -and -not $f.safetyPages.ContainsKey($url))) {
        throw 'Fixture rejected unapproved ARM origin, resource or API version.'
    }
    $f.armCalls++
    if ($uri.AbsolutePath -eq $safetyPolicyId -or $uri.AbsolutePath -in $f.missingResources) {
        $global:LASTEXITCODE = 1
        return '{"error":{"code":"NotFound"}}'
    }
    if ($f.safetyPages.ContainsKey($url)) { return ($f.safetyPages[$url] | ConvertTo-Json -Depth 80) }
    $f.arm[$uri.AbsolutePath] | ConvertTo-Json -Depth 80
}

function Invoke-RestMethod {
    param($Method, $Uri, $Headers, $ContentType, $Body, $TimeoutSec, $OperationTimeoutSeconds, $MaximumRedirection, $MaximumRetryCount, [switch]$SkipCertificateCheck, [switch]$SkipHttpErrorCheck, $StatusCodeVariable)
    $f = $global:api2026Fixture
    $f.httpCalls++
    $request = $Body | ConvertFrom-Json
    if ($Method -ne 'Post' -or $Uri -cne 'https://gateway.example/default/models/openai/v1/chat/completions' -or
        $request.max_completion_tokens -ne 64 -or $request.stream -ne $false -or
        $TimeoutSec -ne 13 -or $MaximumRedirection -ne 0 -or $MaximumRetryCount -ne 0 -or $SkipCertificateCheck -or -not $SkipHttpErrorCheck -or
        ((Get-Command Microsoft.PowerShell.Utility\Invoke-RestMethod).Parameters.ContainsKey('OperationTimeoutSeconds') -and $OperationTimeoutSeconds -ne 13) -or
        $Headers.traceparent -notmatch '^00-[a-f0-9]{32}-[a-f0-9]{16}-01$' -or
        $Headers['x-ms-client-request-id'] -ne '00000000-0000-0000-0000-000000000099') {
        throw 'Unbounded, uncorrelated or untrusted runtime request.'
    }
    $f.requestedAliases.Add($request.model)
    if ($f.transportFailure) { throw 'synthetic-key-do-not-persist MODEL-CONTENT-MUST-NOT-APPEAR transport error' }
    if ($Headers.ContainsKey('Api-Key')) { throw 'The standalone gateway must not use the legacy API-key header.' }
    $expectedCredential = if ($f.authentication -eq 'EntraId') { 'Bearer synthetic-token-do-not-persist' } else { 'Bearer synthetic-key-do-not-persist' }
    $valid = $Headers.Authorization -ceq $expectedCredential
    if ($valid) {
        Set-Variable -Name $StatusCodeVariable -Value $f.positiveStatus -Scope 1
        return @{ choices = @(@{ message = @{ content = 'MODEL-CONTENT-MUST-NOT-APPEAR' } }); usage = @{ prompt_tokens = 8; completion_tokens = $f.completionTokens; total_tokens = 8 + $f.completionTokens; arbitrary = 'MODEL-CONTENT-MUST-NOT-APPEAR' } }
    }
    $expectedInvalid = if ($f.authentication -eq 'EntraId') { 'Bearer synthetic-invalid-token' } else { 'Bearer synthetic-invalid-api-key' }
    if ($Headers.ContainsKey('Authorization') -and $Headers.Authorization -cne $expectedInvalid) { throw 'Unexpected credential-bearing negative request.' }
    Set-Variable -Name $StatusCodeVariable -Value $f.negativeStatus -Scope 1
    @{ error = @{ code = 'Fixture'; message = $f.negativeMessage } }
}

function Get-Arguments {
    $arguments = @{ TerraformDirectory = $entry; SubscriptionId = $subscription; TenantId = $tenant; AllowedResourceGroups = @($groups.Values) }
    foreach ($key in $global:api2026Fixture.extraArguments.Keys) { $arguments[$key] = $global:api2026Fixture.extraArguments[$key] }
    $arguments
}

function Set-PrivateBackendFixture {
    $f = $global:api2026Fixture
    $subnet = "$prefix/resourceGroups/synthetic-platform/providers/Microsoft.Network/virtualNetworks/shared/subnets/backend"
    $f.extraArguments.ExpectedBackendSubnetId = $subnet
    $f.extraArguments.ExpectedBackendPublicNetworkAccess = 'Disabled'
    $f.outputs.gateway_contract.value.backend_subnet_id = $subnet
    $f.state['module.gateway.azapi_resource.gateway'].body.properties.backend = @{ subnet = @{ id = $subnet } }
    $f.arm[$gatewayId].properties.backend = @{ subnet = @{ id = $subnet } }
    $f.outputs.backend_public_network_access = @{ value = @{
        models = 'Disabled'; agents = 'Disabled'; storage = 'Disabled'; registry = 'Disabled'
        monitoring_ingestion = 'Disabled'; monitoring_query = 'Disabled'
    } }
    foreach ($name in @('models', 'agents', 'storage', 'registry')) {
        $value = $f.state["module.gateway.azapi_resource.$name"]
        $value.body.properties.publicNetworkAccess = 'Disabled'
        $f.arm[$value.id].properties.publicNetworkAccess = 'Disabled'
        if ($value.body.properties.networkAcls) {
            $value.body.properties.networkAcls.defaultAction = 'Deny'
            $f.arm[$value.id].properties.networkAcls.defaultAction = 'Deny'
        }
    }
    foreach ($name in @('logs', 'insights')) {
        foreach ($key in @('gateway', 'agents')) {
            $value = $f.state["module.gateway.azapi_resource.$name[`"$key`"]"]
            foreach ($field in @('publicNetworkAccessForIngestion', 'publicNetworkAccessForQuery')) {
                $value.body.properties[$field] = 'Disabled'
                $f.arm[$value.id].properties[$field] = 'Disabled'
            }
        }
    }
}

function Set-ExternalNsgFixture {
    $f = $global:api2026Fixture
    $id = "$($groupIds.gateway)/providers/Microsoft.Network/networkSecurityGroups/external-pe"
    $peSubnet = $f.state['module.gateway.azapi_resource.api2026_subnet["private-endpoints"]'].id
    $rules = @(
        foreach ($rule in @(
            @('AllowVnetInBound', 'Inbound', 'Allow', 65000, 'VirtualNetwork', 'VirtualNetwork'),
            @('AllowAzureLoadBalancerInBound', 'Inbound', 'Allow', 65001, 'AzureLoadBalancer', '*'),
            @('DenyAllInBound', 'Inbound', 'Deny', 65500, '*', '*'),
            @('AllowVnetOutBound', 'Outbound', 'Allow', 65000, 'VirtualNetwork', 'VirtualNetwork'),
            @('AllowInternetOutBound', 'Outbound', 'Allow', 65001, '*', 'Internet'),
            @('DenyAllOutBound', 'Outbound', 'Deny', 65500, '*', '*')
        )) {
            @{ name = $rule[0]; properties = @{
                direction = $rule[1]; access = $rule[2]; priority = $rule[3]
                sourceAddressPrefix = $rule[4]; destinationAddressPrefix = $rule[5]
                protocol = '*'; sourcePortRange = '*'; destinationPortRange = '*'
            } }
        }
    )
    $f.arm[$id] = @{
        id = $id; type = 'Microsoft.Network/networkSecurityGroups'; location = 'swedencentral'
        properties = @{ provisioningState = 'Succeeded'; securityRules = @(); defaultSecurityRules = $rules; subnets = @(@{ id = $peSubnet }) }
    }
    $f.versions[$id] = '2024-05-01'
    $f.arm[$peSubnet].properties.networkSecurityGroup = @{ id = $id }
    $f.extraArguments.ExpectedPrivateEndpointSubnetNsgId = $id
    $f.arm[$id]
}

function Invoke-Fixture([switch]$Probe, [switch]$Negative, [string]$ReportPath) {
    $arguments = Get-Arguments
    if ($ReportPath) { $arguments.ReportPath = $ReportPath }
    if ($Probe) {
        & $script:probe @arguments -Bounded -Authentication $global:api2026Fixture.authentication -MaxOutputTokens 64 -TimeoutSeconds 13 `
            -RunId '00000000-0000-0000-0000-000000000099' -TestNegativeAuthentication:$Negative
    }
    else { & $script:checker @arguments }
}

function Assert-NoDisclosure($Value) {
    $text = $Value | ConvertTo-Json -Depth 40
    if ($text -match 'synthetic-(?:key|token|gateway-connection|agents-connection)-do-not-persist|MODEL-CONTENT-MUST-NOT-APPEAR') {
        throw 'A report/error disclosed a credential, connection string or model content.'
    }
}

function Assert-Rejected([string]$Expected, [switch]$BeforeAzure, [switch]$BeforeArm, [switch]$Probe, [switch]$Negative, [int]$ExpectedHttp = 0, [int]$ExpectedCredentials = 0) {
    $failure = $null
    $path = Join-Path $fixtureDirectory "failure-$caseCount.json"
    try { Invoke-Fixture -Probe:$Probe -Negative:$Negative -ReportPath $path | Out-Null }
    catch { $failure = $_.Exception.Message }
    if (-not $failure -or $failure -notmatch $Expected -or $failure -match 'Unexpected validation failure|Validation or credential acquisition failed') {
        throw "Expected '$Expected', got '$failure' (fixture $caseCount)."
    }
    Assert-NoDisclosure $failure
    if (Test-Path -LiteralPath $path) { Assert-NoDisclosure (Get-Content -LiteralPath $path -Raw) }
    $f = $global:api2026Fixture
    if (($BeforeAzure -and ($f.accountCalls -or $f.armCalls)) -or ($BeforeArm -and $f.armCalls) -or
        $f.credentialCalls -ne $ExpectedCredentials -or $f.httpCalls -ne $ExpectedHttp) {
        throw "Failed gate reached an unexpected account/ARM/credential/inference operation (fixture $caseCount)."
    }
}

try {
    Reset-Fixture
    $reportPath = Join-Path $fixtureDirectory 'configuration.json'
    $result = Invoke-Fixture -ReportPath $reportPath
    if ($result.configurationStatus -cne 'PASS' -or $result.overallStatus -cne 'INCOMPLETE' -or
        $result.checks.'state-and-scope'.evidence.managedResources -ne 34 -or
        $result.checks.'tool-servers'.evidence.toolServers -ne 1 -or
        $result.checks.'tool-servers'.evidence.reachability -cne 'NOT TESTED' -or
        $result.toolServerReachability.status -cne 'NOT TESTED' -or
        $result.checks.roles.evidence.defaultBindings -ne 6 -or $result.aliases.Count -ne 2 -or
        $result.checks.'exporter-topology'.evidence.apiVersion -cne '2025-09-01-preview' -or
        $result.checks.'backend-content-safety'.evidence.coreHarmFilters -ne 8 -or
        $result.checks.'backend-content-safety'.evidence.deploymentBindings -ne 3 -or
        $result.checks.'backend-content-safety'.evidence.readback -cne 'Account policy list' -or
        $result.checks.'backend-content-safety'.evidence.enforcement -cne 'NOT TESTED' -or
        $result.checks.connections.evidence.connections -ne 3 -or
        -not $result.checks.connections.evidence.insightsScopes.project.isDefaultPresent -or
        $result.checks.connections.evidence.insightsScopes.project.isDefault -ne $false -or
        $result.checks.connections.evidence.derivedDefaultSelectionProven -ne $false -or
        $result.telemetryDelivery.status -cne 'NOT TESTED' -or $result.runtime.status -cne 'NOT TESTED' -or
        $global:api2026Fixture.credentialCalls -or $global:api2026Fixture.httpCalls) { throw 'Configuration-only report overstated acceptance or did not verify the full default sample.' }
    Assert-NoDisclosure $result
    Assert-NoDisclosure (Get-Content -LiteralPath $reportPath -Raw)

    Reset-Fixture -PrivateLab
    $nsg = Set-ExternalNsgFixture
    $result = Invoke-Fixture
    $external = $result.checks['private-lab-configuration'].evidence.externalPrivateEndpointNsg
    if ($result.configurationStatus -cne 'PASS' -or $external.status -cne 'VERIFIED' -or $external.id -cne $nsg.id -or
        $result.overallStatus -cne 'INCOMPLETE' -or $global:api2026Fixture.credentialCalls) {
        throw 'Exact external NSG opt-in did not remain scoped and explicit.'
    }
    Assert-NoDisclosure $result

    foreach ($case in @('no-opt-in', 'wrong-subscription', 'not-private-lab', 'managed-id', 'missing-attachment',
        'custom-rule', 'null-custom-rules', 'wrong-default', 'missing-default', 'extended-selector',
        'shared-subnet', 'nic-attachment', 'wrong-location', 'not-ready', 'wrong-returned-id', 'enabled-network-policies', 'route-table')) {
        Reset-Fixture -PrivateLab
        $nsg = Set-ExternalNsgFixture
        $f = $global:api2026Fixture
        $pe = $f.arm[$f.state['module.gateway.azapi_resource.api2026_subnet["private-endpoints"]'].id].properties
        switch ($case) {
            'no-opt-in' { $f.extraArguments.Remove('ExpectedPrivateEndpointSubnetNsgId') }
            'wrong-subscription' { $f.extraArguments.ExpectedPrivateEndpointSubnetNsgId = $nsg.id.Replace($subscription, $tenant) }
            'not-private-lab' { $f.extraArguments.Remove('PrivateLab') }
            'managed-id' { $f.extraArguments.ExpectedPrivateEndpointSubnetNsgId = $f.state['module.gateway.azapi_resource.api2026_nsg["gateway"]'].id }
            'missing-attachment' { $pe.Remove('networkSecurityGroup') }
            'custom-rule' { $nsg.properties.securityRules = @(@{ name = 'unexpected-allow' }) }
            'null-custom-rules' { $nsg.properties.securityRules = $null }
            'wrong-default' { $nsg.properties.defaultSecurityRules[2].properties.access = 'Allow' }
            'missing-default' { $nsg.properties.defaultSecurityRules = @($nsg.properties.defaultSecurityRules | Select-Object -First 5) }
            'extended-selector' { $nsg.properties.defaultSecurityRules[0].properties.sourceAddressPrefixes = @('*') }
            'shared-subnet' { $nsg.properties.subnets += @{ id = $f.state['module.gateway.azapi_resource.api2026_subnet["verification-client"]'].id } }
            'nic-attachment' { $nsg.properties.networkInterfaces = @(@{ id = 'unapproved-interface' }) }
            'wrong-location' { $nsg.location = 'westeurope' }
            'not-ready' { $nsg.properties.provisioningState = 'Updating' }
            'wrong-returned-id' { $nsg.id += '-other' }
            'enabled-network-policies' { $pe.privateEndpointNetworkPolicies = 'Enabled' }
            'route-table' { $pe.routeTable = @{ id = "$($groupIds.gateway)/providers/Microsoft.Network/routeTables/unapproved" } }
        }
        Assert-Rejected 'API2026:' -BeforeAzure:($case -in @('wrong-subscription', 'not-private-lab', 'managed-id'))
    }

    Reset-Fixture -PrivateLab
    $null = Set-ExternalNsgFixture
    $result = Invoke-Fixture -Probe
    if ($result.status -cne 'PASS' -or $global:api2026Fixture.httpCalls -ne 2) { throw 'Bounded probe did not forward the exact NSG opt-in.' }
    Assert-NoDisclosure $result

    Reset-Fixture -PrivateLab
    $f = $global:api2026Fixture
    foreach ($id in $f.outputs.model_deployment_ids.value.Keys) {
        $f.arm["$providerId/models/$id"].properties.Remove('apiFormat')
    }
    $f.arm["$workspace/telemetryExporters/appinsights"].properties.Remove('kind')
    $diagnostic = $f.state['module.gateway.azapi_resource.api2026_blob_read_diagnostics["lab"]']
    $f.arm[$diagnostic.id].properties.logAnalyticsDestinationType = $null
    $result = Invoke-Fixture
    if ($result.configurationStatus -cne 'PASS' -or $result.readbackProjections.Count -ne 5 -or
        $result.overallStatus -cne 'INCOMPLETE' -or $result.telemetryDelivery.status -cne 'NOT TESTED' -or
        $f.credentialCalls -or $f.httpCalls) { throw 'Readback projection handling hid limitations or reached inference.' }
    Assert-NoDisclosure $result

    foreach ($case in @('explicit-format', 'null-format', 'missing-provider', 'wrong-provider', 'null-kind', 'lowercase-kind', 'state-lowercase-kind', 'state-null-destination', 'wrong-destination', 'missing-destination', 'null-wrong-workspace')) {
        Reset-Fixture -PrivateLab
        $f = $global:api2026Fixture
        $catalog = $f.arm["$providerId/models/gpt-latest"].properties
        $exporter = $f.arm["$workspace/telemetryExporters/appinsights"].properties
        $diagnostic = $f.state['module.gateway.azapi_resource.api2026_blob_read_diagnostics["lab"]']
        $liveDiagnostic = $f.arm[$diagnostic.id].properties
        switch ($case) {
            'explicit-format' { $catalog.apiFormat = 'Other' }
            'null-format' { $catalog.apiFormat = $null }
            'missing-provider' { $catalog.Remove('apiFormat'); $catalog.Remove('providerKind') }
            'wrong-provider' { $catalog.Remove('apiFormat'); $catalog.providerKind = 'Other' }
            'null-kind' { $exporter.kind = $null }
            'lowercase-kind' { $exporter.kind = 'applicationInsights' }
            'state-lowercase-kind' { $f.state['module.gateway.azapi_resource.telemetry_exporter'].body.properties.kind = 'applicationInsights' }
            'state-null-destination' { $diagnostic.body.properties.logAnalyticsDestinationType = $null }
            'wrong-destination' { $liveDiagnostic.logAnalyticsDestinationType = 'AzureDiagnostics' }
            'missing-destination' { $liveDiagnostic.Remove('logAnalyticsDestinationType') }
            'null-wrong-workspace' { $liveDiagnostic.logAnalyticsDestinationType = $null; $liveDiagnostic.workspaceId += '-other' }
        }
        Assert-Rejected 'API2026:' -BeforeAzure:($case -like 'state-*')
    }

    Reset-Fixture
    Set-PrivateBackendFixture
    $result = Invoke-Fixture -Probe
    if ($result.status -cne 'PASS' -or $global:api2026Fixture.credentialCalls -ne 1 -or $global:api2026Fixture.httpCalls -ne 2) {
        throw 'Exact external subnet and disabled-backend expectations were not forwarded through the bounded probe.'
    }

    foreach ($case in @('unapproved-subnet', 'mismatched-subnet', 'cross-subscription', 'encoded-subnet', 'output-access', 'state-access', 'managed-scope')) {
        Reset-Fixture
        Set-PrivateBackendFixture
        $f = $global:api2026Fixture
        switch ($case) {
            'unapproved-subnet' { $f.extraArguments.Remove('ExpectedBackendSubnetId') }
            'mismatched-subnet' { $f.extraArguments.ExpectedBackendSubnetId += '-different' }
            'cross-subscription' { $f.extraArguments.ExpectedBackendSubnetId = $f.extraArguments.ExpectedBackendSubnetId.Replace($subscription, '00000000-0000-0000-0000-000000000099') }
            'encoded-subnet' { $f.extraArguments.ExpectedBackendSubnetId += '%2Fother' }
            'output-access' { $f.outputs.backend_public_network_access.value.storage = 'Enabled' }
            'state-access' { $f.state['module.gateway.azapi_resource.storage'].body.properties.publicNetworkAccess = 'Enabled' }
            'managed-scope' { $f.state['module.gateway.azapi_resource.storage'].id = $storageId.Replace($groups.agents, 'synthetic-platform') }
        }
        Assert-Rejected 'API2026:' -Probe -BeforeAzure
    }

    Reset-Fixture
    Set-PrivateBackendFixture
    $global:api2026Fixture.arm[$storageId].properties.publicNetworkAccess = 'Enabled'
    Assert-Rejected 'storage properties.publicNetworkAccess' -Probe

    Reset-Fixture
    $path = Join-Path $fixtureDirectory 'independent-sharing-failure.json'
    $global:api2026Fixture.arm["$projectId/connections/agents-insights"].properties.isSharedToAll = $true
    $failure = $null
    try { Invoke-Fixture -ReportPath $path | Out-Null } catch { $failure = $_.Exception.Message }
    $partial = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    if ($failure -notmatch 'metadata/sharing.isSharedToAll' -or $partial.configurationStatus -cne 'FAIL' -or
        $partial.checks.connections.status -cne 'FAIL' -or
        @('models-and-routes', 'backend-content-safety', 'roles', 'exporter-topology', 'tool-servers').Where({ $partial.checks[$_].status -cne 'PASS' }).Count -or
        $global:api2026Fixture.credentialCalls -or $global:api2026Fixture.httpCalls) {
        throw 'Connection sharing failure hid independent checks or weakened the overall gate.'
    }
    Assert-NoDisclosure $partial

    Reset-Fixture
    $null = Add-FixtureResource insights_connection '' 'Microsoft.CognitiveServices/accounts/connections@2025-06-01' "$agentsId/connections/agents-insights" $agentsId @{
        properties = @{ category = 'AppInsights'; authType = 'ApiKey'; isSharedToAll = $true; target = $global:api2026Fixture.outputs.application_insights_ids.value.agents }
    }
    Assert-Rejected 'API2026:' -BeforeAzure -Probe

    foreach ($case in @('project-parent', 'project-metadata', 'derived-default', 'user-list-binding')) {
        Reset-Fixture
        $connection = $global:api2026Fixture.state['module.gateway.azapi_resource.project_insights_connection["agents"]']
        switch ($case) {
            'project-parent' { $connection.parent_id = $agentsId }
            'project-metadata' { $connection.body.properties.metadata.ResourceId = 'agents-insights' }
            'derived-default' { $connection.body.properties.isDefault = $true }
            'user-list-binding' { $connection.body.properties.sharedUserList = @($projectId) }
        }
        Assert-Rejected 'API2026:' -BeforeAzure -Probe
    }
    foreach ($case in @('project-404', 'project-sharing', 'project-metadata', 'project-credential')) {
        Reset-Fixture
        $f = $global:api2026Fixture
        $properties = $f.arm["$projectId/connections/agents-insights"].properties
        switch ($case) {
            'project-404' { $f.missingResources = @("$projectId/connections/agents-insights") }
            'project-sharing' { $properties.isSharedToAll = $true }
            'project-metadata' { $properties.metadata.ResourceId = 'agents-insights' }
            'project-credential' { $properties.credentials.key = 'synthetic-wrong-secret' }
        }
        Assert-Rejected 'API2026:' -Probe
    }

    Reset-Fixture
    [array]::Reverse($global:api2026Fixture.arm[$safetyPolicyId].properties.contentFilters)
    $null = Invoke-Fixture

    Reset-Fixture
    $secondPage = "https://management.azure.com${safetyCollectionId}?api-version=2025-04-01-preview&%24skiptoken=second"
    $global:api2026Fixture.arm[$safetyCollectionId] = @{ value = @(); nextLink = $secondPage }
    $global:api2026Fixture.safetyPages[$secondPage] = @{ value = @($global:api2026Fixture.arm[$safetyPolicyId]) }
    $result = Invoke-Fixture
    if ($result.checks.'backend-content-safety'.evidence.pages -ne 2) { throw 'Safety policy pagination was not completed.' }

    foreach ($case in @('missing', 'duplicate', 'invalid-list', 'host', 'scope', 'version', 'cycle')) {
        Reset-Fixture
        $f = $global:api2026Fixture
        switch ($case) {
            'missing' { $f.arm[$safetyCollectionId].value = @() }
            'duplicate' { $f.arm[$safetyCollectionId].value += Copy-Json $f.arm[$safetyPolicyId] }
            'invalid-list' { $f.arm[$safetyCollectionId].value = $f.arm[$safetyPolicyId] }
            'host' { $f.arm[$safetyCollectionId].nextLink = "https://other.example${safetyCollectionId}?api-version=2025-04-01-preview" }
            'scope' { $f.arm[$safetyCollectionId].nextLink = "https://management.azure.com${agentsId}/raiPolicies?api-version=2025-04-01-preview" }
            'version' { $f.arm[$safetyCollectionId].nextLink = "https://management.azure.com${safetyCollectionId}?api-version=2025-06-01" }
            'cycle' { $f.arm[$safetyCollectionId].nextLink = "https://management.azure.com${safetyCollectionId}?api-version=2025-04-01-preview" }
        }
        Assert-Rejected 'backend content filter' -Probe
    }

    Reset-Fixture -AllowedClientCidrs @('203.0.113.42/32', '2001:db8:1234::/48')
    $null = Invoke-Fixture

    foreach ($case in @('action', 'ranges', 'missing')) {
        Reset-Fixture -AllowedClientCidrs @('203.0.113.42/32', '2001:db8:1234::/48')
        $policies = $global:api2026Fixture.arm["$providerId/models/gpt-latest"].properties.policies
        switch ($case) {
            'action' { $policies[3].action = 'Deny' }
            'ranges' { $policies[3].cidrRanges = @('192.0.2.42/32') }
            'missing' { $global:api2026Fixture.arm["$providerId/models/gpt-latest"].properties.policies = @($policies[0..2]) }
        }
        Assert-Rejected 'catalog and ordered policies' -Probe
    }

    Reset-Fixture
    $null = Add-FixtureRole gateway-models-user-fixture $gatewayId '00000000-0000-0000-0000-000000000009' User 'a6b68e3d-a1f0-4c60-8678-237c050cf4ea'
    $result = Invoke-Fixture
    if ($result.checks.roles.evidence.configuredCallerBindings -ne 1) { throw 'Explicit scoped caller was not checked.' }

    Reset-Fixture
    $global:api2026Fixture.arm[$global:api2026Fixture.defaultRoleId].properties.principalId = $gatewayPrincipal.ToUpperInvariant()
    $null = Invoke-Fixture

    foreach ($case in @('family', 'contract', 'metadata-missing', 'version-newer', 'telemetry-version', 'configured-sku', 'backend-input', 'backend-payload', 'group-map', 'duplicate-group', 'wrong-subscription', 'encoded-id', 'key-id', 'project-url', 'state-scope', 'state-type', 'state-version', 'alias-backend', 'alias-format', 'connection-metadata', 'caller-scope', 'missing-role', 'state-tenant', 'missing-safety-binding', 'unsupported-gateway-safety')) {
        Reset-Fixture
        $f = $global:api2026Fixture
        switch ($case) {
            'family' { $f.outputs.gateway_contract.value.resource_type = 'Microsoft.ApiManagement/service' }
            'contract' { $f.outputs.gateway_contract.value.name = 'legacy' }
            'metadata-missing' { $f.outputs.Remove('gateway_api_versions') }
            'version-newer' { $f.outputs.gateway_api_versions.value.aliases = '2026-10-01-preview' }
            'telemetry-version' { $f.outputs.gateway_api_versions.value.telemetry = '2026-09-01-preview' }
            'configured-sku' { $f.state['module.gateway.azapi_resource.gateway'].body.sku = @{ name = 'Consumption' } }
            'backend-input' { $f.outputs.gateway_contract.value.backend_subnet_id = "$($groupIds.gateway)/providers/Microsoft.Network/virtualNetworks/shared/subnets/backend" }
            'backend-payload' { $f.state['module.gateway.azapi_resource.gateway'].body.properties.backend = @{ subnet = @{ id = "$($groupIds.gateway)/providers/Microsoft.Network/virtualNetworks/shared/subnets/backend" } } }
            'group-map' { $f.outputs.resource_groups.value.models = 'outside-approved-groups' }
            'duplicate-group' { $f.outputs.resource_groups.value.models = $groups.gateway }
            'wrong-subscription' { $f.outputs.gateway_id.value = $gatewayId.Replace($subscription, '00000000-0000-0000-0000-000000000099') }
            'encoded-id' { $f.outputs.gateway_id.value = "$gatewayId%2FapiKeys%2Fdefault" }
            'key-id' { $f.outputs.gateway_api_key_id.value = "$keyId?api-version=unapproved" }
            'project-url' { $f.outputs.project_endpoint.value = 'https://other.example/api/projects/project' }
            'state-scope' { $f.state['module.gateway.azapi_resource.storage'].id = $storageId.Replace($groups.agents, 'outside-approved-groups') }
            'state-type' { $f.state['module.gateway.azapi_resource.runtime_api_key'].type = 'Microsoft.ApiManagement/service/apiKeys@2025-09-01-preview' }
            'state-version' { $f.state['module.gateway.azapi_resource.gateway'].type = 'Microsoft.ApiManagement/aigateways@2025-09-01-preview' }
            'alias-backend' { $f.outputs.model_alias_configuration.value.'mini-router'.backend_models[0].deployment = 'not-configured' }
            'alias-format' { $f.outputs.model_alias_configuration.value.'mini-router'.api_format = 'Other' }
            'connection-metadata' { $f.state['module.gateway.azapi_resource.project_insights_connection["agents"]'].body.properties.metadata.ResourceId = 'agents-insights' }
            'caller-scope' { $null = Add-FixtureRole gateway-models-user-fixture $modelsId '00000000-0000-0000-0000-000000000009' User 'a6b68e3d-a1f0-4c60-8678-237c050cf4ea' }
            'missing-role' { $f.resources.RemoveAt($f.resources.Count - 1) }
            'state-tenant' { $f.state['module.gateway.azapi_resource.gateway'].identity[0].tenant_id = '00000000-0000-0000-0000-000000000099' }
            'missing-safety-binding' { $f.state['module.gateway.azapi_resource.model_deployment["gpt-latest"]'].body.properties.Remove('raiPolicyName') }
            'unsupported-gateway-safety' { $f.state['module.gateway.azapi_resource.catalog_model["gpt-latest"]'].body.properties.policies += @{ type = 'contentSafety'; hateSeverity = 'Medium' } }
        }
        Assert-Rejected 'API2026:' -BeforeAzure -Probe
    }
    foreach ($case in @('tool-server-version', 'tool-server-output', 'tool-server-unlisted', 'tool-server-unmanaged', 'tool-server-id', 'tool-server-http', 'tool-server-credential-url', 'tool-server-type', 'tool-server-namespace', 'tool-server-transport', 'tool-server-endpoints', 'tool-server-policy')) {
        Reset-Fixture
        $f = $global:api2026Fixture
        $toolServer = $f.state['module.gateway.azapi_resource.mcp_tool_server["microsoft-learn"]'].body.properties
        switch ($case) {
            'tool-server-version' { $f.outputs.gateway_api_versions.value.tool_servers = '2026-09-01-preview' }
            'tool-server-output' { $f.outputs.Remove('mcp_tool_server_ids') }
            'tool-server-unlisted' { $f.outputs.mcp_tool_server_ids.value = @{} }
            'tool-server-unmanaged' { $f.outputs.mcp_tool_server_ids.value.other = "$workspace/toolServers/other" }
            'tool-server-id' { $f.outputs.mcp_tool_server_ids.value.'microsoft-learn' = "$workspace/toolServers/other" }
            'tool-server-http' { $toolServer.endpoints[0].mcp.url = 'http://learn.microsoft.com/api/mcp' }
            'tool-server-credential-url' { $toolServer.endpoints[0].mcp.url = 'https://user:secret@learn.microsoft.com/api/mcp' }
            'tool-server-type' { $toolServer.type = 'openApi' }
            'tool-server-namespace' { $toolServer.endpoints[0].namespace = 'other' }
            'tool-server-transport' { $toolServer.endpoints[0].mcp.transport = 'sse' }
            'tool-server-endpoints' { $toolServer.endpoints += Copy-Json $toolServer.endpoints[0] }
            'tool-server-policy' { $toolServer.policies[0].counterKey = @('ipAddress') }
        }
        Assert-Rejected 'API2026:' -BeforeAzure -Probe
    }

    Reset-Fixture -SingleGroup
    Set-ExistingGroupFixture
    $result = Invoke-Fixture
    $evidence = $result.checks.'state-and-scope'.evidence
    if ($result.configurationStatus -cne 'PASS' -or $evidence.managedResources -ne $global:api2026Fixture.resources.Count -or
        $evidence.resourceGroupOwnership -notlike 'Existing group*') {
        throw 'Existing-group acceptance treated the reused group as managed.'
    }
    Reset-Fixture -SingleGroup
    Set-ExistingGroupFixture
    $result = Invoke-Fixture -Probe
    if ($result.status -cne 'PASS' -or $result.configurationStatus -cne 'PASS') { throw 'The bounded probe did not forward the existing-group switch.' }
    foreach ($case in @('no-switch', 'false-contract', 'missing-contract-key', 'managed-group', 'three-groups', 'private-lab')) {
        if ($case -ceq 'three-groups') { Reset-Fixture } elseif ($case -ceq 'private-lab') { Reset-Fixture -PrivateLab } else { Reset-Fixture -SingleGroup }
        $f = $global:api2026Fixture
        if ($case -ceq 'managed-group') {
            $f.outputs.gateway_contract.value.existing_resource_group = $true
            $f.extraArguments.ExistingResourceGroup = $true
        }
        else { Set-ExistingGroupFixture }
        switch ($case) {
            'no-switch' { $f.extraArguments.Remove('ExistingResourceGroup') }
            'false-contract' { $f.outputs.gateway_contract.value.existing_resource_group = $false }
            'missing-contract-key' { $f.outputs.gateway_contract.value.Remove('existing_resource_group') }
        }
        Assert-Rejected 'API2026:' -BeforeAzure -Probe
    }
    foreach ($url in @('http://gateway.example', 'https://gateway.example:444', 'https://user:password@gateway.example', 'https://gateway.example/path', 'https://gateway.example?query=secret', 'https://127.0.0.1', 'https://gateway..example')) {
        Reset-Fixture
        $global:api2026Fixture.outputs.gateway_endpoint.value = $url
        Assert-Rejected 'HTTPS service origin' -BeforeAzure -Probe
    }
    foreach ($field in @('id', 'tenantId')) {
        Reset-Fixture
        $global:api2026Fixture.account[$field] = '00000000-0000-0000-0000-000000000099'
        Assert-Rejected 'wrong tenant or subscription' -BeforeArm -Probe
    }
    foreach ($case in @('not-ready', 'missing-frontend', 'region', 'gateway-origin', 'arm-host', 'arm-id', 'identity', 'model-project-management', 'provider-target', 'route-order', 'policy', 'request-limit', 'request-window', 'request-counter', 'connection-sharing', 'connection-metadata', 'storage-target', 'role-principal', 'role-scope', 'exporter-kind', 'exporter-capture', 'exporter-secret', 'tool-server-url', 'tool-server-limit', 'tool-server-missing', 'safety-binding', 'safety-policy-id', 'safety-policy-mode', 'safety-disabled', 'safety-nonblocking', 'safety-threshold', 'safety-missing-completion', 'safety-duplicate', 'safety-jailbreak', 'safety-protected-text', 'safety-protected-code')) {
        Reset-Fixture
        $f = $global:api2026Fixture
        switch ($case) {
            'not-ready' { $f.arm[$gatewayId].properties.provisioningState = 'Creating' }
            'missing-frontend' {
                $f.arm[$gatewayId].properties.Remove('frontend')
                $f.arm[$gatewayId].properties.gatewayUrl = 'https://gateway.example'
            }
            'region' { $f.arm[$gatewayId].location = 'eastus2' }
            'gateway-origin' { $f.outputs.gateway_endpoint.value = 'https://attacker.example' }
            'arm-host' { $f.arm[$gatewayId].properties.frontend.defaultHostname = 'gateway.example/path' }
            'arm-id' { $f.arm[$gatewayId].id = "$gatewayId-other" }
            'identity' { $f.arm[$gatewayId].identity.principalId = '00000000-0000-0000-0000-000000000099' }
            'model-project-management' { $f.arm[$modelsId].properties.allowProjectManagement = $false }
            'provider-target' { $f.arm[$providerId].properties.foundry.endpoint = 'https://other.example/' }
            'route-order' { [array]::Reverse($f.arm["$workspace/aliases/primary-router"].properties.backendModels) }
            'policy' { $f.arm["$providerId/models/gpt-latest"].properties.policies[0].count = 1 }
            'request-limit' { $f.arm["$providerId/models/gpt-latest"].properties.policies[2].callsPerPeriod = 1 }
            'request-window' { $f.arm["$providerId/models/gpt-latest"].properties.policies[2].periodSeconds = 30 }
            'request-counter' { $f.arm["$providerId/models/gpt-latest"].properties.policies[2].counterKey = @('ipAddress') }
            'connection-sharing' { $f.arm["$projectId/connections/syntheticregistry-conn"].properties.isSharedToAll = $true }
            'connection-metadata' { $f.arm["$projectId/connections/agents-insights"].properties.metadata.ResourceId = 'agents-insights' }
            'storage-target' { $f.arm[$storageId].properties.primaryEndpoints.blob = 'https://other.blob.core.windows.net/' }
            'role-principal' { $f.arm[$f.defaultRoleId].properties.principalId = '00000000-0000-0000-0000-000000000099' }
            'role-scope' { $f.arm[$f.defaultRoleId].properties.scope = $prefix }
            'exporter-kind' { $f.arm["$workspace/telemetryExporters/appinsights"].properties.kind = 'OpenTelemetry' }
            'exporter-capture' { $f.arm["$workspace/telemetryExporters/appinsights"].properties.payloadCapture = $true }
            'exporter-secret' { $f.arm["$workspace/telemetryExporters/appinsights"].properties.applicationInsights.connectionString = 'synthetic-wrong-secret' }
            'tool-server-url' { $f.arm["$workspace/toolServers/microsoft-learn"].properties.endpoints[0].mcp.url = 'https://other.example/mcp' }
            'tool-server-limit' { $f.arm["$workspace/toolServers/microsoft-learn"].properties.policies[0].callsPerPeriod = 1000 }
            'tool-server-missing' { $f.missingResources = @("$workspace/toolServers/microsoft-learn") }
            'safety-binding' { $f.arm["$modelsId/deployments/gpt-latest"].properties.raiPolicyName = 'Microsoft.Default' }
            'safety-policy-id' { $f.arm[$safetyPolicyId].id = "$modelsId/raiPolicies/Other" }
            'safety-policy-mode' { $f.arm[$safetyPolicyId].properties.mode = 'Asynchronous_filter' }
            'safety-disabled' { $f.arm[$safetyPolicyId].properties.contentFilters[0].enabled = $false }
            'safety-nonblocking' { $f.arm[$safetyPolicyId].properties.contentFilters[0].blocking = $false }
            'safety-threshold' { $f.arm[$safetyPolicyId].properties.contentFilters[0].severityThreshold = 'High' }
            'safety-missing-completion' { $f.arm[$safetyPolicyId].properties.contentFilters = @($f.arm[$safetyPolicyId].properties.contentFilters | Where-Object { $_.source -ne 'Completion' }) }
            'safety-duplicate' { $f.arm[$safetyPolicyId].properties.contentFilters += Copy-Json $f.arm[$safetyPolicyId].properties.contentFilters[0] }
            'safety-jailbreak' { $f.arm[$safetyPolicyId].properties.contentFilters[8].blocking = $false }
            'safety-protected-text' { $f.arm[$safetyPolicyId].properties.contentFilters[9].enabled = $false }
            'safety-protected-code' { $f.arm[$safetyPolicyId].properties.contentFilters[10].enabled = $false }
        }
        Assert-Rejected 'API2026:' -Probe
    }
    foreach ($mode in @('ApiKey', 'EntraId')) {
        Reset-Fixture
        $global:api2026Fixture.authentication = $mode
        $path = Join-Path $fixtureDirectory "$mode-runtime.json"
        $result = Invoke-Fixture -Probe -Negative -ReportPath $path
        if ($result.status -cne 'PASS' -or $result.overallStatus -cne 'INCOMPLETE' -or $result.negativeAuthentication.status -cne 'PASS' -or
            $global:api2026Fixture.credentialCalls -ne 1 -or $global:api2026Fixture.httpCalls -ne 4 -or
            @($global:api2026Fixture.requestedAliases | Sort-Object -Unique).Count -ne 2 -or
            $result.telemetryDelivery.status -cne 'NOT TESTED' -or
            ($mode -eq 'EntraId' -and $global:api2026Fixture.keyUrl)) { throw 'Bounded runtime/authentication evidence was incomplete or used a fallback.' }
        Assert-NoDisclosure $result
        Assert-NoDisclosure (Get-Content -LiteralPath $path -Raw)
    }
    Reset-Fixture
    $global:api2026Fixture.authentication = 'EntraId'
    $global:api2026Fixture.negativeStatus = 403
    $global:api2026Fixture.negativeMessage = 'Authentication failed: invalid bearer token.'
    $result = Invoke-Fixture -Probe -Negative
    if ($result.negativeAuthentication.status -cne 'PASS') { throw 'Explicit new-family Entra rejection was not classified.' }

    Reset-Fixture
    foreach ($key in $global:api2026Fixture.outputs.model_api_configuration.value.Keys) {
        $global:api2026Fixture.outputs.model_api_configuration.value[$key].endpoints = @('/openai/v1/responses')
        $global:api2026Fixture.state['module.gateway.azapi_resource.catalog_model["' + $key + '"]'].body.properties.supportedEndpoints = @('/openai/v1/responses')
        $global:api2026Fixture.arm["$providerId/models/$key"].properties.supportedEndpoints = @('/openai/v1/responses')
    }
    foreach ($alias in $global:api2026Fixture.outputs.model_alias_configuration.value.Values) { $alias.endpoints = @('/openai/v1/responses') }
    Assert-Rejected 'Unsupported alias API' -Probe

    foreach ($status in @(200, 400, 403, 429, 500)) {
        Reset-Fixture
        $global:api2026Fixture.negativeStatus = $status
        $global:api2026Fixture.negativeMessage = 'Access denied by network policy.'
        Assert-Rejected 'Authentication rejection was not established' -Probe -Negative -ExpectedHttp 3 -ExpectedCredentials 1
    }
    foreach ($mode in @('ApiKey', 'EntraId')) {
        Reset-Fixture
        $global:api2026Fixture.authentication = $mode
        $global:api2026Fixture.credentialExit = 1
        Assert-Rejected 'Unable to (retrieve|acquire)' -Probe -ExpectedCredentials 1
    }
    Reset-Fixture
    $global:api2026Fixture.transportFailure = $true
    Assert-Rejected 'not retried' -Probe -ExpectedHttp 1 -ExpectedCredentials 1
    foreach ($status in @(302, 503)) {
        Reset-Fixture
        $global:api2026Fixture.positiveStatus = $status
        Assert-Rejected 'not proven' -Probe -ExpectedHttp 1 -ExpectedCredentials 1
    }
    Reset-Fixture
    $global:api2026Fixture.completionTokens = 65
    Assert-Rejected 'exceeded the explicit output cap' -Probe -ExpectedHttp 1 -ExpectedCredentials 1

    Reset-Fixture
    $arguments = Get-Arguments
    $failure = $null
    try { & $probe @arguments -Bounded -TimeoutSeconds 13 | Out-Null } catch { $failure = $_.Exception.Message }
    if ($failure -notmatch 'explicit -MaxOutputTokens' -or $global:api2026Fixture.accountCalls) { throw 'An omitted output cap did not stop before external activity.' }
    Reset-Fixture
    $arguments = Get-Arguments
    $failure = $null
    try { & $probe @arguments -Bounded -MaxOutputTokens 64 | Out-Null } catch { $failure = $_.Exception.Message }
    if ($failure -notmatch 'explicit -TimeoutSeconds' -or $global:api2026Fixture.accountCalls) { throw 'An omitted timeout did not stop before external activity.' }
    Reset-Fixture
    $arguments = Get-Arguments
    $failure = $null
    try { & $probe @arguments -MaxOutputTokens 64 | Out-Null } catch { $failure = $_.Exception.Message }
    if ($failure -notmatch 'require -Bounded' -or $global:api2026Fixture.accountCalls) { throw 'Bounded flags were silently applied to legacy mode.' }

    foreach ($scriptPath in @($checker, $probe)) {
        Reset-Fixture
        $arguments = Get-Arguments
        $arguments.ReportPath = $reportPath
        if ($scriptPath -eq $probe) { $arguments.Bounded = $true; $arguments.MaxOutputTokens = 64; $arguments.TimeoutSeconds = 13 }
        $previous = Get-Content -LiteralPath $reportPath -Raw
        $failure = $null
        try { & $scriptPath @arguments | Out-Null } catch { $failure = $_.Exception.Message }
        if (-not $failure -or $global:api2026Fixture.accountCalls -or (Get-Content -LiteralPath $reportPath -Raw) -cne $previous) {
            throw 'Existing evidence was overwritten or its rejection allowed external activity.'
        }
    }

    "API2026 acceptance checks passed ($caseCount cases; Terraform/Azure/HTTP mocked; no live acceptance)."
}
finally {
    Remove-Item -LiteralPath $fixtureDirectory -Recurse -Force
    Remove-Variable -Name api2026Fixture -Scope Global -ErrorAction SilentlyContinue
}
