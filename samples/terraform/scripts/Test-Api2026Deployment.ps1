#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TerraformDirectory,
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][guid]$TenantId,
    [Parameter(Mandatory)][ValidateCount(1, 3)][string[]]$AllowedResourceGroups,
    [switch]$SingleResourceGroup,
    [switch]$ExistingResourceGroup,
    [switch]$PrivateLab,
    [string]$ExpectedPrivateEndpointSubnetNsgId,
    [string]$ExpectedBackendSubnetId,
    [ValidateSet('Enabled', 'Disabled')][string]$ExpectedBackendPublicNetworkAccess,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$subscription = $SubscriptionId.ToString()
$tenant = $TenantId.ToString()
$root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TerraformDirectory)
$prefix = "/subscriptions/$subscription"
$checks = [ordered]@{}
$readbackProjections = [Collections.Generic.List[object]]::new()
$report = [ordered]@{
    schemaVersion = 2
    contract = 'api2026gateway'
    scope = 'Standalone configuration with explicitly scoped backend networking; not private ingress, private traffic proof or a running agent application.'
    subscriptionId = $subscription
    tenantId = $tenant
    startedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    configurationStatus = 'FAIL'
    overallStatus = 'INCOMPLETE'
    checks = $checks
    readbackProjections = $readbackProjections
    runtime = @{ status = 'NOT TESTED' }
    telemetryDelivery = @{
        status = 'NOT TESTED'
        detail = 'Exporter topology is separate from delivery. Probe run/trace IDs are client evidence only; no telemetry table or server-side correlation support is assumed.'
    }
    idempotence = @{ status = 'NOT TESTED'; detail = 'The coordinator must inspect a separate no-change plan.' }
    failoverAndPolicyEnforcement = @{ status = 'NOT TESTED' }
    toolServerReachability = @{ status = 'NOT TESTED'; detail = 'Registration only; the remote MCP server and gateway tool routing are not called.' }
    privateIngress = @{ status = 'NOT IMPLEMENTED' }
    agentRuntime = @{ status = 'NOT TESTED' }
    portal = @{ status = 'NOT TESTED' }
}
$stateByAddress = @{}
$expectedResources = @{}
$liveResources = @{}
$canWriteReport = $false

function Stop-Api2026([string]$Message) { throw "API2026: $Message" }

function Read-Json([string]$Text) {
    try { ConvertFrom-Json -InputObject $Text -AsHashtable -Depth 100 }
    catch { Stop-Api2026 'Invalid JSON response; raw content omitted.' }
}

function Invoke-Check([string]$Name, [scriptblock]$Action, [switch]$ContinueOnFailure) {
    $checks[$Name] = @{ status = 'FAIL' }
    try {
        $checks[$Name].evidence = & $Action
        $checks[$Name].status = 'PASS'
    }
    catch {
        $checks[$Name].error = if ($_.Exception.Message -like 'API2026: *') { $_.Exception.Message } else { 'API2026: Unexpected validation failure; raw details omitted.' }
        if (-not $ContinueOnFailure) { throw }
    }
}

function Assert-Map($Value, [string]$Label) {
    if ($Value -isnot [Collections.IDictionary]) { Stop-Api2026 "Missing or invalid $Label." }
}

function Assert-Name($Value) {
    if ($Value -isnot [string] -or $Value -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,259}$') {
        Stop-Api2026 'Invalid resource name in the selected state.'
    }
}

function Assert-Guid($Value) {
    if ($Value -isnot [string] -or $Value -notmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' -or
        $Value -eq [guid]::Empty.ToString()) {
        Stop-Api2026 'Missing or invalid identity/resource UUID.'
    }
}

function Assert-AllowedId($Id) {
    if ($Id -isnot [string] -or $Id -match '[%\\?#\s]' -or
        $Id -notmatch ('^' + [regex]::Escape($prefix) + '/resourceGroups/([^/]+)(?:/providers/[a-zA-Z0-9.]+(?:/[a-zA-Z0-9_.-]+)+)?$') -or
        $Matches[1] -notin $AllowedResourceGroups -or $Id -match '/\.{1,2}(?:/|$)') {
        Stop-Api2026 'Resource ID is not canonical or is outside the approved subscription/group allowlist.'
    }
}

function Assert-BackendSubnetId($Id) {
    if ($Id -isnot [string] -or $Id -match '[%\\?#\s]' -or
        $Id -notmatch ('^' + [regex]::Escape($prefix) + '/resourceGroups/[a-zA-Z0-9][a-zA-Z0-9_.()-]{0,89}/providers/Microsoft\.Network/virtualNetworks/[a-zA-Z0-9][a-zA-Z0-9_.-]*/subnets/[a-zA-Z0-9][a-zA-Z0-9_.-]*$') -or
        $Id -match '/\.{1,2}(?:/|$)') {
        Stop-Api2026 'Invalid same-subscription backend subnet ID.'
    }
}

function Get-ClientNetwork($Value) {
    # Mirrors the Terraform rules, including no leading zeros in IPv4 parts or prefix lengths, and returns
    # the canonical network, so ARM clearing host bits or respelling an IPv6 address is not reported as drift.
    $match = if ($Value -is [string] -and $Value -cnotmatch '(?:^|[.:])0[0-9]+[.]|[.]0[0-9]+/') {
        [regex]::Match($Value, '^([0-9A-Fa-f:.]+)/([1-9][0-9]{0,2})\z')
    }
    if ($null -eq $match -or -not $match.Success) { Stop-Api2026 'Invalid gateway client IP range.' }
    $address, $bits = $match.Groups[1].Value, [int]$match.Groups[2].Value
    $ip = $null
    if ($address -cmatch '^[0-9]{1,3}(?:[.][0-9]{1,3}){3}$') {
        $octets = [int[]]$address.Split('.')
        if ($bits -gt 32 -or @($octets | Where-Object { $_ -gt 255 }).Count) { Stop-Api2026 'Invalid gateway client IP range.' }
        $bytes = [byte[]]$octets
    }
    elseif ($address.Contains(':') -and [Net.IPAddress]::TryParse($address, [ref]$ip) -and
        $ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6 -and $bits -le 128) {
        $bytes = $ip.GetAddressBytes()
    }
    else { Stop-Api2026 'Invalid gateway client IP range.' }
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $kept = [Math]::Min(8, [Math]::Max(0, $bits - 8 * $i))
        $bytes[$i] = $bytes[$i] -band ((0xFF -shl (8 - $kept)) -band 0xFF)
    }
    "$([Net.IPAddress]::new($bytes))/$bits"
}

function Get-GatewayIpFilter($Policies, [string]$Label, [switch]$State) {
    # Returns $null without an ipFilter, otherwise the range count and sorted canonical networks.
    if ($Policies -isnot [array]) { Stop-Api2026 "Invalid $Label policy list." }
    foreach ($policy in $Policies) {
        Assert-Map $policy "$Label policy"
        if ($policy.type -isnot [string] -or [string]::IsNullOrWhiteSpace($policy.type)) { Stop-Api2026 "Invalid $Label policy type." }
    }
    $filters = @($Policies | Where-Object { $_.type -ieq 'ipFilter' })
    if ($filters.Count -gt 1) { Stop-Api2026 "More than one $Label IP filter." }
    if (-not $filters.Count) { return $null }
    $filter = $filters[0]
    $ranges = $filter.cidrRanges
    if ($filter.action -isnot [string] -or $filter.action -ine 'Allow' -or $ranges -isnot [array] -or -not $ranges.Count) {
        Stop-Api2026 "The $Label IP filter must be a non-empty allow list."
    }
    $networks = @($ranges | ForEach-Object { Get-ClientNetwork $_ })
    if ($State -and ($filter.type -cne 'ipFilter' -or $filter.action -cne 'Allow' -or
            (@($filter.Keys | Sort-Object) -join ',') -cne 'action,cidrRanges,type' -or
            [Collections.Generic.HashSet[string]]::new([string[]]$ranges, [StringComparer]::Ordinal).Count -ne $ranges.Count)) {
        Stop-Api2026 'The state IP filter differs from the module contract.'
    }
    @{ count = $ranges.Count; networks = @($networks | Sort-Object -Unique) -join ',' }
}

function Get-Origin($Value) {
    $uri = $null
    $ip = $null
    if ($Value -isnot [string] -or $Value -match '[\\\s%]' -or
        -not [uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -cne 'https' -or -not $uri.IsDefaultPort -or $uri.UserInfo -or
        $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -ne '/' -or
        $uri.Host -notmatch '^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$' -or
        [Net.IPAddress]::TryParse($uri.Host, [ref]$ip)) {
        Stop-Api2026 'Expected a credential-free HTTPS service origin, without path, query, fragment or IP address.'
    }
    $uri.GetLeftPart([UriPartial]::Authority).ToLowerInvariant()
}

function Get-Output([string]$Name) {
    if (-not $outputs.Contains($Name)) { Stop-Api2026 "Missing Terraform output: $Name." }
    Assert-Map $outputs[$Name] "Terraform output $Name"
    if (-not $outputs[$Name].Contains('value')) { Stop-Api2026 "Missing Terraform output value: $Name." }
    $outputs[$Name].value
}

function Get-StateResources($Module) {
    $Module.resources
    foreach ($child in $Module.child_modules) { Get-StateResources $child }
}

function Get-Address([string]$Name, [string]$Key = '', [string]$TerraformType = 'azapi_resource') {
    $address = "module.gateway.$TerraformType.$Name"
    if ($Key) { $address += '["' + $Key + '"]' }
    $address
}

function Get-StateValue([string]$Name, [string]$Key = '', [string]$TerraformType = 'azapi_resource') {
    $address = Get-Address $Name $Key $TerraformType
    if (-not $stateByAddress.ContainsKey($address)) { Stop-Api2026 "Missing expected managed resource: $Name." }
    $stateByAddress[$address].values
}

function Register-Resource([string]$Name, [string]$Key, [string]$Type, [string]$Id, [string]$Parent, [string]$TerraformType = 'azapi_resource') {
    Assert-AllowedId $Id
    $value = Get-StateValue $Name $Key $TerraformType
    Assert-Map $value 'managed resource values'
    Assert-Map $value.body 'managed resource body'
    if ($Name -in @('resource_group', 'gateway', 'models', 'agents', 'project', 'storage', 'registry', 'logs', 'insights') -and
        ($value.location -isnot [string] -or [string]::IsNullOrWhiteSpace($value.location))) {
        Stop-Api2026 "Missing configured resource region: $Name."
    }
    $wrongOwner = if ($TerraformType -ceq 'azapi_update_resource') {
        $Name -cne 'disk_access' -or $Key -cne 'client' -or -not $PrivateLab -or $value.resource_id -ine $Id
    }
    elseif ($TerraformType -ceq 'azapi_resource_action') {
        $Name -cne 'gateway_ip_filter' -or $Key -cne 'default' -or $value.resource_id -ine $Id -or
        $value.method -cne 'PATCH' -or $value.when -cne 'apply' -or -not [string]::IsNullOrEmpty($value.action)
    }
    else { $value.parent_id -ine $Parent -or $value.name -cne $Id.Split('/')[-1] }
    if ($value.id -ine $Id -or $value.type -cne $Type -or $wrongOwner) {
        Stop-Api2026 "Managed resource type, name, parent or ID mismatch: $Name."
    }
    $expectedResources[(Get-Address $Name $Key $TerraformType)] = $value
    $value
}

function Assert-ConfiguredValue($Actual, $Expected, [string]$Label) {
    if ($Expected -is [Collections.IDictionary]) {
        Assert-Map $Actual $Label
        foreach ($key in $Expected.Keys) {
            if ($null -eq $Expected[$key] -and -not $Actual.Contains($key)) { continue }
            if (-not $Actual.Contains($key)) { Stop-Api2026 "Missing configured field: $Label.$key." }
            Assert-ConfiguredValue $Actual[$key] $Expected[$key] "$Label.$key"
        }
    }
    elseif ($Expected -is [array]) {
        if ($Actual -isnot [array] -or $Actual.Count -ne $Expected.Count) {
            Stop-Api2026 "Configured array mismatch: $Label."
        }
        for ($i = 0; $i -lt $Expected.Count; $i++) {
            Assert-ConfiguredValue $Actual[$i] $Expected[$i] "$Label[$i]"
        }
    }
    elseif ($Expected -is [string]) {
        $matches = $Actual -is [string] -and (
            $(if ($Expected.StartsWith('/subscriptions/') -or $Expected -match '^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$') { $Actual -ieq $Expected } else { $Actual -ceq $Expected })
        )
        if (-not $matches) { Stop-Api2026 "Configured value mismatch: $Label." }
    }
    elseif ($Expected -is [bool]) {
        if ($Actual -isnot [bool] -or $Actual -ne $Expected) { Stop-Api2026 "Configured flag mismatch: $Label." }
    }
    elseif ($null -eq $Expected) {
        if ($null -ne $Actual) { Stop-Api2026 "Unexpected configured value: $Label." }
    }
    elseif ($Actual -is [string] -or $Actual -is [bool] -or $null -eq $Actual -or $Actual -ne $Expected) {
        Stop-Api2026 "Configured number mismatch: $Label."
    }
}

function Invoke-AzureJson([string[]]$Arguments) {
    $text = & az @Arguments --subscription $subscription --only-show-errors --output json 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Api2026 'Azure CLI read failed; raw response omitted.' }
    Read-Json ($text -join "`n")
}

function Read-Resource([string]$Name, [string]$Key = '', [switch]$Ready, [string]$TerraformType = 'azapi_resource') {
    $address = Get-Address $Name $Key $TerraformType
    if (-not $expectedResources.ContainsKey($address)) { Stop-Api2026 'Resource read was not admitted by state/scope validation.' }
    $expected = $expectedResources[$address]
    Assert-AllowedId $expected.id
    $type, $version = $expected.type -split '@', 2
    $resource = Invoke-AzureJson @('rest', '--method', 'get', '--url', "https://management.azure.com$($expected.id)?api-version=$version")
    Assert-Map $resource 'ARM resource response'
    if ($resource.id -ine $expected.id -or $resource.type -ine $type) {
        Stop-Api2026 "ARM returned a different resource: $Name."
    }
    if ($Ready -and $resource.properties.provisioningState -cne 'Succeeded') {
        Stop-Api2026 "Resource is not ready: $Name."
    }
    if ($expected.location -and
        ([string]$resource.location).Replace(' ', '') -ine ([string]$expected.location).Replace(' ', '')) {
        Stop-Api2026 "Resource region differs from selected state: $Name."
    }
    $liveResources[$address] = $resource
    $resource
}

function Assert-KeylessProvider($Authentication) {
    Assert-ConfiguredValue $Authentication @{
        kind = 'ManagedIdentity'; managedIdentity = @{ resource = 'https://cognitiveservices.azure.com/' }
    } 'provider managed identity authentication'
    if (@($Authentication.Keys | Where-Object { $_ -cnotin @('kind', 'managedIdentity') -and $null -ne $Authentication[$_] }).Count -or
        @($Authentication.managedIdentity.Keys | Where-Object { $_ -cnotin @('resource', 'clientId') -and $null -ne $Authentication.managedIdentity[$_] }).Count -or
        -not [string]::IsNullOrWhiteSpace($Authentication.managedIdentity.clientId)) {
        Stop-Api2026 'Backend keys or an unapproved managed-identity selector are not permitted.'
    }
}

. (Join-Path $PSScriptRoot 'Api2026-PrivateLab.ps1')

try {
    Invoke-Check 'state-and-scope' {
        $script:physicalGroupKeys = if ($SingleResourceGroup) { @('gateway') } else { @('gateway', 'models', 'agents') }
        if ($SubscriptionId -eq [guid]::Empty -or $TenantId -eq [guid]::Empty -or
            -not (Test-Path -LiteralPath $root -PathType Container) -or
            $AllowedResourceGroups.Count -ne $physicalGroupKeys.Count -or
            @($AllowedResourceGroups | Sort-Object -Unique).Count -ne $physicalGroupKeys.Count -or
            @($AllowedResourceGroups | Where-Object { $_ -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.()-]{0,89}$' -or $_.EndsWith('.') }).Count) {
            Stop-Api2026 'Explicit directory, nonempty target UUIDs and exactly three distinct valid groups (one with -SingleResourceGroup) are required.'
        }
        if ($PrivateLab -and (-not $SingleResourceGroup -or $ExpectedBackendPublicNetworkAccess -cne 'Disabled')) {
            Stop-Api2026 'Private-lab acceptance requires explicit single-group and Disabled backend-access expectations.'
        }
        if ($ExistingResourceGroup -and (-not $SingleResourceGroup -or $PrivateLab)) {
            Stop-Api2026 'Existing-group acceptance requires -SingleResourceGroup and is not supported with -PrivateLab.'
        }
        if ($ExpectedPrivateEndpointSubnetNsgId) {
            Assert-AllowedId $ExpectedPrivateEndpointSubnetNsgId
            if (-not $PrivateLab -or $ExpectedPrivateEndpointSubnetNsgId -notmatch (
                '^' + [regex]::Escape("$prefix/resourceGroups/$($AllowedResourceGroups[0])") +
                '/providers/Microsoft\.Network/networkSecurityGroups/[a-zA-Z0-9][a-zA-Z0-9_.-]*$')) {
                Stop-Api2026 'External private-endpoint NSG requires PrivateLab and an exact same-group NSG ID.'
            }
        }
        if ($ReportPath) {
            $script:ReportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportPath)
            if (Test-Path -LiteralPath $ReportPath) { Stop-Api2026 'Report path already exists; preserve evidence and choose a new file.' }
            if (-not (Test-Path -LiteralPath (Split-Path $ReportPath -Parent) -PathType Container)) {
                Stop-Api2026 'Report parent directory must already exist.'
            }
            $script:canWriteReport = $true
        }
        $text = & terraform "-chdir=$root" output -json 2>$null
        if ($LASTEXITCODE -ne 0) { Stop-Api2026 'Cannot read selected Terraform outputs.' }
        $script:outputs = Read-Json ($text -join "`n")
        Assert-Map $outputs 'Terraform outputs'
        $contract = Get-Output 'gateway_contract'
        Assert-Map $contract 'gateway contract'
        $contractKeys = @('name', 'resource_type', 'backend_subnet_id')
        if ($SingleResourceGroup -or $PrivateLab -or $contract.Contains('single_resource_group') -or $contract.Contains('private_lab')) {
            $contractKeys += @('single_resource_group', 'private_lab')
            Assert-ConfiguredValue $contract @{ single_resource_group = [bool]$SingleResourceGroup; private_lab = [bool]$PrivateLab } 'explicit layout contract'
        }
        if ($ExistingResourceGroup -or $contract.Contains('existing_resource_group')) {
            $contractKeys += 'existing_resource_group'
            Assert-ConfiguredValue $contract @{ existing_resource_group = [bool]$ExistingResourceGroup } 'explicit existing-group contract'
        }
        if (@(Compare-Object $contractKeys @($contract.Keys)).Count -or
            $contract.name -cne '2026' -or $contract.resource_type -cne 'Microsoft.ApiManagement/aigateways') {
            Stop-Api2026 'Selected state is not the standalone API2026 gateway contract.'
        }
        if ($ExpectedBackendSubnetId) {
            Assert-BackendSubnetId $ExpectedBackendSubnetId
            if ($contract.backend_subnet_id -ine $ExpectedBackendSubnetId) {
                Stop-Api2026 'Backend subnet differs from the explicitly approved subnet ID.'
            }
        }
        $versions = Get-Output 'gateway_api_versions'
        Assert-Map $versions 'gateway API versions'
        $expectedVersions = @{ gateway = '2026-09-01-preview'; catalog = '2026-09-01-preview'; aliases = '2026-09-01-preview'; api_keys = '2026-09-01-preview'; telemetry = '2025-09-01-preview'; tool_servers = '2025-09-01-preview' }
        if ($versions.Count -ne $expectedVersions.Count) { Stop-Api2026 'Unexpected API-version metadata.' }
        Assert-ConfiguredValue $versions $expectedVersions 'gateway_api_versions'
        $script:groups = Get-Output 'resource_groups'
        Assert-Map $groups 'resource groups'
        if ($groups.Count -ne 3 -or @(Compare-Object @('gateway', 'models', 'agents') @($groups.Keys)).Count -or
            @(Compare-Object $AllowedResourceGroups @($groups.Values | Sort-Object -Unique)).Count -or
            @($groups.Values | Sort-Object -Unique).Count -ne $physicalGroupKeys.Count) {
            Stop-Api2026 'Outputs must map gateway/models/agents to exactly the approved distinct groups and selected layout.'
        }
        $script:groupIds = @{}
        foreach ($key in @('gateway', 'models', 'agents')) { $groupIds[$key] = "$prefix/resourceGroups/$($groups[$key])" }
        $script:gatewayId = Get-Output 'gateway_id'
        $script:modelsId = Get-Output 'foundry_models_id'
        $script:projectId = Get-Output 'project_id'
        foreach ($id in @($gatewayId, $modelsId, $projectId)) { Assert-AllowedId $id }
        foreach ($entry in @(
            @($gatewayId, "$($groupIds.gateway)/providers/Microsoft.ApiManagement/aigateways/"),
            @($modelsId, "$($groupIds.models)/providers/Microsoft.CognitiveServices/accounts/"),
            @($projectId, "$($groupIds.agents)/providers/Microsoft.CognitiveServices/accounts/")
        )) {
            if (-not $entry[0].StartsWith($entry[1], [StringComparison]::OrdinalIgnoreCase)) { Stop-Api2026 'Output resource family/group mismatch.' }
        }
        Assert-Name $gatewayId.Substring(("$($groupIds.gateway)/providers/Microsoft.ApiManagement/aigateways/").Length)
        Assert-Name $modelsId.Substring(("$($groupIds.models)/providers/Microsoft.CognitiveServices/accounts/").Length)
        if ($projectId -notmatch '/accounts/([a-zA-Z0-9_.-]+)/projects/([a-zA-Z0-9_.-]+)$') { Stop-Api2026 'Invalid project resource ID.' }
        $script:agentsId = $projectId -replace '/projects/[^/]+$', ''
        Assert-ConfiguredValue (Get-Output 'project_endpoint') "https://$($agentsId.Split('/')[-1]).services.ai.azure.com/api/projects/$($projectId.Split('/')[-1])" 'project endpoint'
        $script:stateOrigin = Get-Origin (Get-Output 'gateway_endpoint')
        $script:keyId = Get-Output 'gateway_api_key_id'
        if ($keyId -ine "$gatewayId/apiKeys/default") { Stop-Api2026 'API-key ID is not the selected gateway default key.' }
        $storageName = Get-Output 'storage_account_name'
        if ($storageName -cnotmatch '^[a-z0-9]{3,24}$') { Stop-Api2026 'Invalid storage account name.' }
        $registryHost = Get-Output 'container_registry_endpoint'
        if ($registryHost -cnotmatch '^([a-zA-Z0-9]{5,50})\.azurecr\.io$') { Stop-Api2026 'Invalid registry endpoint.' }
        $registryName = $Matches[1]
        $script:storageId = "$($groupIds.agents)/providers/Microsoft.Storage/storageAccounts/$storageName"
        $script:registryId = "$($groupIds.agents)/providers/Microsoft.ContainerRegistry/registries/$registryName"
        $script:insightsIds = Get-Output 'application_insights_ids'
        Assert-Map $insightsIds 'Insights IDs'
        if ($insightsIds.Count -ne 2 -or @(Compare-Object @('gateway', 'agents') @($insightsIds.Keys)).Count) { Stop-Api2026 'Expected two Insights destinations.' }
        foreach ($key in @('gateway', 'agents')) {
            Assert-AllowedId $insightsIds[$key]
            $base = "$($groupIds[$key])/providers/Microsoft.Insights/components/"
            if (-not $insightsIds[$key].StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { Stop-Api2026 'Insights destination group/type mismatch.' }
            Assert-Name $insightsIds[$key].Substring($base.Length)
        }
        $script:monitoring = Get-Output 'gateway_monitoring'
        Assert-Map $monitoring 'gateway monitoring'
        if ($monitoring.Count -ne 3 -or $monitoring.kind -cne 'applicationInsights' -or $monitoring.insights_id -ine $insightsIds.gateway) { Stop-Api2026 'Expected the new-family Application Insights destination.' }
        Assert-AllowedId $monitoring.log_analytics_id
        $script:deployments = Get-Output 'model_deployment_ids'
        $script:modelApis = Get-Output 'model_api_configuration'
        $script:aliases = Get-Output 'model_alias_configuration'
        foreach ($map in @($deployments, $modelApis, $aliases)) { Assert-Map $map 'model/alias metadata'; if (-not $map.Count) { Stop-Api2026 'Empty model/alias metadata.' } }
        if (@(Compare-Object @($deployments.Keys) @($modelApis.Keys)).Count) { Stop-Api2026 'Model API metadata differs from the deployment list.' }
        foreach ($key in $deployments.Keys) {
            Assert-Name $key
            if ($deployments[$key] -ine "$modelsId/deployments/$key") { Stop-Api2026 'Model deployment ID does not belong to the selected models account.' }
            Assert-Map $modelApis[$key] 'model API metadata'
            if ([string]::IsNullOrWhiteSpace($modelApis[$key].api_format) -or
                $modelApis[$key].endpoints -isnot [array] -or -not $modelApis[$key].endpoints.Count -or
                @($modelApis[$key].endpoints | Where-Object { $_ -isnot [string] -or $_ -cnotmatch '^/[a-zA-Z0-9_/-]+$' }).Count) {
                Stop-Api2026 'Invalid model API format/endpoints.'
            }
        }
        $callableNames = @()
        foreach ($key in $aliases.Keys) {
            Assert-Name $key
            $alias = $aliases[$key]
            Assert-Map $alias 'alias metadata'
            if ($alias.alias_name -isnot [string] -or [string]::IsNullOrWhiteSpace($alias.alias_name) -or
                $alias.backend_models -isnot [array] -or -not $alias.backend_models.Count -or
                $alias.endpoints -isnot [array] -or -not $alias.endpoints.Count) { Stop-Api2026 'Incomplete callable alias metadata.' }
            foreach ($backend in $alias.backend_models) {
                if (-not $deployments.Contains($backend.deployment)) { Stop-Api2026 'Alias references an unconfigured deployment.' }
            }
            $format = $modelApis[$alias.backend_models[0].deployment].api_format
            $commonEndpoints = @($modelApis[$alias.backend_models[0].deployment].endpoints)
            foreach ($backend in $alias.backend_models) {
                if ($modelApis[$backend.deployment].api_format -cne $format) { Stop-Api2026 'Alias backends use different API formats.' }
                $commonEndpoints = @($commonEndpoints | Where-Object { $_ -cin $modelApis[$backend.deployment].endpoints })
            }
            Assert-ConfiguredValue $alias.api_format $format 'alias API format'
            Assert-ConfiguredValue $alias.endpoints @($commonEndpoints | Sort-Object -Unique) 'alias common endpoints'
            $callableNames += $alias.alias_name
        }
        if (@($callableNames | Sort-Object -Unique).Count -ne $callableNames.Count) { Stop-Api2026 'Duplicate callable aliases.' }
        $text = & terraform "-chdir=$root" show -json 2>$null
        if ($LASTEXITCODE -ne 0) { Stop-Api2026 'Cannot read the selected Terraform state.' }
        $state = Read-Json ($text -join "`n")
        $ownedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($resource in @(Get-StateResources $state.values.root_module | Where-Object { $_.mode -eq 'managed' })) {
            $normalResource = $resource.type -ceq 'azapi_resource' -and $resource.address -match '^module\.gateway\.azapi_resource\.'
            $ownedDiskUpdate = $PrivateLab -and $resource.type -ceq 'azapi_update_resource' -and $resource.address -ceq 'module.gateway.azapi_update_resource.disk_access["client"]'
            $ownedIpFilter = $resource.type -ceq 'azapi_resource_action' -and $resource.address -ceq 'module.gateway.azapi_resource_action.gateway_ip_filter["default"]'
            if ((-not $normalResource -and -not $ownedDiskUpdate -and -not $ownedIpFilter) -or $stateByAddress.ContainsKey($resource.address)) {
                Stop-Api2026 'Unexpected or duplicate managed address; use the isolated API entry state.'
            }
            Assert-AllowedId $resource.values.id
            if (-not $ownedIds.Add($resource.values.id)) { Stop-Api2026 'Duplicate ARM ownership in the selected Terraform state.' }
            $stateByAddress[$resource.address] = $resource
        }
        # A reused group is read by Terraform, not managed; the inventory count below rejects a managed group.
        if (-not $ExistingResourceGroup) {
            foreach ($key in $physicalGroupKeys) { $null = Register-Resource resource_group $key 'Microsoft.Resources/resourceGroups@2021-04-01' $groupIds[$key] $prefix }
        }
        $script:gatewayState = Register-Resource gateway '' 'Microsoft.ApiManagement/aigateways@2026-09-01-preview' $gatewayId $groupIds.gateway
        Assert-Map $gatewayState.body.properties 'gateway properties'
        if ($gatewayState.body.Contains('sku') -or
            @($gatewayState.body.properties.Keys | Where-Object { $_ -cne 'backend' }).Count) {
            Stop-Api2026 'Expected the standalone root without an explicit SKU or legacy properties.'
        }
        if ($contract.backend_subnet_id) {
            Assert-BackendSubnetId $contract.backend_subnet_id
            if (-not $ExpectedBackendSubnetId) { Assert-AllowedId $contract.backend_subnet_id }
            Assert-ConfiguredValue $gatewayState.body.properties.backend @{ subnet = @{ id = $contract.backend_subnet_id } } 'backend subnet metadata'
        }
        elseif ($gatewayState.body.properties.backend) { Stop-Api2026 'Backend subnet differs from contract output.' }
        $null = Register-Resource models '' 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' $modelsId $groupIds.models
        $null = Register-Resource agents '' 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' $agentsId $groupIds.agents
        $script:projectState = Register-Resource project '' 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' $projectId $agentsId
        $null = Register-Resource storage '' 'Microsoft.Storage/storageAccounts@2024-01-01' $storageId $groupIds.agents
        $null = Register-Resource registry '' 'Microsoft.ContainerRegistry/registries@2023-07-01' $registryId $groupIds.agents
        foreach ($name in @('models', 'agents')) {
            Assert-ConfiguredValue (Get-StateValue $name).body.properties.disableLocalAuth $true "$name local authentication disabled"
        }
        Assert-ConfiguredValue (Get-StateValue storage).body.properties.allowSharedKeyAccess $false 'Storage shared keys disabled'
        foreach ($key in @('gateway', 'agents')) {
            $name = (Get-StateValue logs $key).name
            Assert-Name $name
            $null = Register-Resource logs $key 'Microsoft.OperationalInsights/workspaces@2023-09-01' "$($groupIds[$key])/providers/Microsoft.OperationalInsights/workspaces/$name" $groupIds[$key]
            $null = Register-Resource insights $key 'Microsoft.Insights/components@2020-02-02' $insightsIds[$key] $groupIds[$key]
        }
        if ($ExpectedBackendPublicNetworkAccess) {
            if ($ExpectedBackendPublicNetworkAccess -ceq 'Disabled' -and -not $contract.backend_subnet_id) {
                Stop-Api2026 'Disabled backend access requires the configured outbound subnet.'
            }
            $backendAccess = Get-Output 'backend_public_network_access'
            Assert-Map $backendAccess 'backend public access metadata'
            if (@(Compare-Object @('models', 'agents', 'storage', 'registry', 'monitoring_ingestion', 'monitoring_query') @($backendAccess.Keys)).Count) {
                Stop-Api2026 'Unexpected backend public access metadata.'
            }
            foreach ($key in $backendAccess.Keys) {
                Assert-ConfiguredValue $backendAccess[$key] $ExpectedBackendPublicNetworkAccess 'requested backend public access'
            }
            foreach ($name in @('models', 'agents', 'storage', 'registry')) {
                Assert-ConfiguredValue (Get-StateValue $name).body.properties.publicNetworkAccess $ExpectedBackendPublicNetworkAccess "$name requested public access"
            }
            foreach ($key in @('gateway', 'agents')) {
                foreach ($name in @('logs', 'insights')) {
                    foreach ($field in @('publicNetworkAccessForIngestion', 'publicNetworkAccessForQuery')) {
                        Assert-ConfiguredValue (Get-StateValue $name $key).body.properties[$field] $ExpectedBackendPublicNetworkAccess "$name requested $field"
                    }
                }
            }
        }
        if ($monitoring.log_analytics_id -ine (Get-StateValue logs gateway).id) { Stop-Api2026 'Gateway Log Analytics output differs from state.' }
        $workspace = "$gatewayId/workspaces/default"
        $providerId = "$workspace/modelProviders/foundry"
        $provider = Register-Resource foundry_provider '' 'Microsoft.ApiManagement/aigateways/workspaces/modelProviders@2026-09-01-preview' $providerId $workspace
        $null = Get-Origin $provider.body.properties.foundry.endpoint
        Assert-ConfiguredValue $provider.body.properties @{
            kind = 'Foundry'
            foundry = @{ resourceIds = @($modelsId); authentication = @{ kind = 'ManagedIdentity'; managedIdentity = @{ resource = 'https://cognitiveservices.azure.com/' } } }
        } 'provider account/authentication'
        Assert-KeylessProvider $provider.body.properties.foundry.authentication
        foreach ($key in $deployments.Keys) {
            $deployment = Register-Resource model_deployment $key 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' $deployments[$key] $modelsId
            Assert-ConfiguredValue $deployment.body.properties.raiPolicyName 'Microsoft.DefaultV2' 'backend content filter binding'
            $catalog = Register-Resource catalog_model $key 'Microsoft.ApiManagement/aigateways/workspaces/modelProviders/models@2026-09-01-preview' "$providerId/models/$key" $providerId
            Assert-ConfiguredValue $catalog.body.properties.deployment.resourceId $deployments[$key] 'catalog deployment'
            Assert-ConfiguredValue $catalog.body.properties.apiFormat $modelApis[$key].api_format 'catalog API format'
            Assert-ConfiguredValue $catalog.body.properties.supportedEndpoints $modelApis[$key].endpoints 'catalog endpoints'
            if ($catalog.body.properties.policies -isnot [array] -or
                @($catalog.body.properties.policies | Where-Object { $_.type -cnotin @('tokenLimit', 'costLimit', 'requestRateLimit', 'ipFilter') }).Count) {
                Stop-Api2026 'Unsupported standalone model policy; gateway contentSafety is not a backend safety control.'
            }
        }
        foreach ($key in $aliases.Keys) {
            $alias = Register-Resource model_alias $key 'Microsoft.ApiManagement/aigateways/workspaces/aliases@2026-09-01-preview' "$workspace/aliases/$key" $workspace
            $backends = @($aliases[$key].backend_models | ForEach-Object {
                @{ resourceId = "$providerId/models/$($_.deployment)"; priority = $_.priority; weight = $_.weight }
            })
            Assert-ConfiguredValue $alias.body.properties @{ aliasName = $aliases[$key].alias_name; backendModels = $backends } 'state alias routes'
        }
        $null = Register-Resource runtime_api_key '' 'Microsoft.ApiManagement/aigateways/apiKeys@2026-09-01-preview' $keyId $gatewayId
        $exporter = Register-Resource telemetry_exporter '' 'Microsoft.ApiManagement/aigateways/workspaces/telemetryExporters@2025-09-01-preview' "$workspace/telemetryExporters/appinsights" $workspace
        Assert-ConfiguredValue $exporter.body.properties @{ kind = 'ApplicationInsights'; payloadCapture = $false } 'state exporter'
        if ($exporter.body.properties.applicationInsights.resourceId -ine $insightsIds.gateway) { Stop-Api2026 'Exporter destination is outside the selected Insights target.' }
        $script:toolServers = Get-Output 'mcp_tool_server_ids'
        Assert-Map $toolServers 'MCP tool server IDs'
        foreach ($key in $toolServers.Keys) {
            if ($key -cnotmatch '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$') { Stop-Api2026 'Invalid MCP tool server name.' }
            if ($toolServers[$key] -ine "$workspace/toolServers/$key") { Stop-Api2026 'MCP tool server ID does not belong to the selected gateway workspace.' }
            $toolServer = Register-Resource mcp_tool_server $key 'Microsoft.ApiManagement/aigateways/workspaces/toolServers@2025-09-01-preview' $toolServers[$key] $workspace
            Assert-Map $toolServer.body.properties 'MCP tool server properties'
            Assert-ConfiguredValue $toolServer.body.properties @{
                type = 'mcp'
                endpoints = @(@{ namespace = $key; kind = 'mcp'; mcp = @{ transport = 'streamableHttp' } })
                policies = @(@{ type = 'requestRateLimit'; counterKey = @('identity') })
            } 'state MCP tool server'
            $url = $toolServer.body.properties.endpoints[0].mcp.url
            $uri = $null
            if ($url -isnot [string] -or $url -match '[\\\s]' -or -not [uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri) -or
                $uri.Scheme -cne 'https' -or $uri.UserInfo -or [string]::IsNullOrEmpty($uri.Host)) {
                Stop-Api2026 'Expected a credential-free HTTPS MCP server URL.'
            }
        }
        $script:gatewayPolicyState = $null
        if ($stateByAddress.ContainsKey((Get-Address gateway_ip_filter default azapi_resource_action))) {
            $policyUpdate = Register-Resource gateway_ip_filter default 'Microsoft.ApiManagement/aigateways/workspaces@2025-09-01-preview' $workspace $gatewayId azapi_resource_action
            if ((@($policyUpdate.body.Keys) -join ',') -cne 'properties' -or $policyUpdate.body.properties -isnot [Collections.IDictionary] -or
                (@($policyUpdate.body.properties.Keys) -join ',') -cne 'policies') {
                Stop-Api2026 'The gateway policy update must only replace the default workspace policy list.'
            }
            $script:gatewayPolicyState = @{ ipFilter = Get-GatewayIpFilter $policyUpdate.body.properties.policies 'state gateway' -State }
        }
        $storageConnection = Register-Resource storage_connection '' 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' "$projectId/connections/$storageName" $projectId
        $registryConnection = Register-Resource registry_connection '' 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' "$projectId/connections/$registryName-conn" $projectId
        $insightsName = $insightsIds.agents.Split('/')[-1]
        $projectInsightsConnection = Register-Resource project_insights_connection agents 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' "$projectId/connections/$insightsName" $projectId
        Assert-ConfiguredValue $storageConnection.body.properties @{
            category = 'AzureStorageAccount'; authType = 'AAD'
            target = "https://$storageName.blob.core.windows.net/"; metadata = @{ ApiType = 'Azure'; ResourceId = $storageId }
        } 'storage connection scope'
        Assert-ConfiguredValue $registryConnection.body.properties @{
            category = 'ContainerRegistry'; authType = 'ManagedIdentity'; isSharedToAll = $false
            target = $registryHost; metadata = @{ ResourceId = $registryId }
            credentials = @{ clientId = $projectState.identity[0].principal_id; resourceId = $registryId }
        } 'registry connection scope'
        Assert-ConfiguredValue $projectInsightsConnection.body.properties @{
            category = 'AppInsights'; authType = 'ApiKey'; isSharedToAll = $false
            target = $insightsIds.agents; metadata = @{ ApiType = 'Azure'; ResourceId = $insightsIds.agents; location = $projectState.location }
        } 'project Insights connection scope'
        foreach ($connection in @($projectInsightsConnection)) {
            if ($connection.body.properties.Contains('isDefault') -or $connection.body.properties.Contains('sharedUserList')) {
                Stop-Api2026 'Do not configure the derived Insights default or use a user list as project binding.'
            }
        }
        foreach ($identity in @($gatewayState.identity[0], $projectState.identity[0])) {
            Assert-Guid $identity.principal_id
            if ($identity.tenant_id -ine $tenant) { Stop-Api2026 'State runtime identity belongs to a different tenant.' }
            if ($identity.type -cne 'SystemAssigned' -or $identity.identity_ids) { Stop-Api2026 'The gateway/backend project must retain their own SystemAssigned identities.' }
        }
        $script:roleExpectations = @{
            'gateway-foundry-user' = @($modelsId, $gatewayState.identity[0].principal_id, 'ServicePrincipal', '53ca6127-db72-4b80-b1b0-d745d6d5456d')
            'project-storage' = @($storageId, $projectState.identity[0].principal_id, 'ServicePrincipal', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
            'project-acr-pull' = @($registryId, $projectState.identity[0].principal_id, 'ServicePrincipal', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
            'project-contributor' = @($agentsId, $projectState.identity[0].principal_id, 'ServicePrincipal', '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68')
            'project-openai-user' = @($agentsId, $projectState.identity[0].principal_id, 'ServicePrincipal', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
            'project-user' = @($agentsId, $projectState.identity[0].principal_id, 'ServicePrincipal', 'a97b65f3-24c7-4388-baec-2e87135dc908')
        }
        foreach ($address in @($stateByAddress.Keys)) {
            if ($address -match '^module\.gateway\.azapi_resource\.role_assignment\["(gateway-models-user-[a-zA-Z0-9_-]+)"\]$') {
                $key = $Matches[1]
                $properties = $stateByAddress[$address].values.body.properties
                Assert-Guid $properties.principalId
                if ($properties.principalType -cnotin @('User', 'Group', 'ServicePrincipal')) { Stop-Api2026 'Invalid configured gateway caller principal type.' }
                $roleExpectations[$key] = @($gatewayId, $properties.principalId, $properties.principalType, 'a6b68e3d-a1f0-4c60-8678-237c050cf4ea')
            }
        }
        $script:callerCount = $roleExpectations.Count - 6
        $script:developerCount = 0
        $developerAddress = Get-Address role_assignment developer-storage
        if ($stateByAddress.ContainsKey($developerAddress)) {
            $properties = $stateByAddress[$developerAddress].values.body.properties
            Assert-Guid $properties.principalId
            if ($properties.principalType -cnotin @('User', 'Group', 'ServicePrincipal')) { Stop-Api2026 'Invalid configured developer principal type.' }
            $cognitiveRoles = @{ contributor = '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68'; 'openai-user' = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'; user = 'a97b65f3-24c7-4388-baec-2e87135dc908' }
            foreach ($account in @('models', 'agents')) {
                foreach ($role in $cognitiveRoles.Keys) {
                    $scope = if ($account -eq 'models') { $modelsId } else { $agentsId }
                    $roleExpectations["developer-$account-$role"] = @($scope, $properties.principalId, $properties.principalType, $cognitiveRoles[$role])
                }
            }
            $roleExpectations['developer-storage'] = @($storageId, $properties.principalId, $properties.principalType, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
            $script:developerCount = 7
        }
        foreach ($key in $roleExpectations.Keys) {
            $expected = $roleExpectations[$key]
            $role = Get-StateValue role_assignment $key
            Assert-Guid $role.name
            $null = Register-Resource role_assignment $key 'Microsoft.Authorization/roleAssignments@2022-04-01' "$($expected[0])/providers/Microsoft.Authorization/roleAssignments/$($role.name)" $expected[0]
            Assert-ConfiguredValue $role.body.properties @{
                principalId = $expected[1]; principalType = $expected[2]
                roleDefinitionId = "$prefix/providers/Microsoft.Authorization/roleDefinitions/$($expected[3])"
            } 'state role binding'
            if ($role.body.properties.condition) { Stop-Api2026 'Unexpected conditional role binding.' }
        }
        if ($PrivateLab) { Register-Api2026PrivateLab }
        if ($expectedResources.Count -ne $stateByAddress.Count) { Stop-Api2026 'State contains resources outside the supported standalone workload, selected private layout and explicit caller/developer grants.' }
        @{
            groups = $groups; managedResources = $expectedResources.Count; versions = $versions; toolServers = $toolServers.Count
            resourceGroupOwnership = $(if ($ExistingResourceGroup) { 'Existing group read by Terraform; not managed or deleted' } else { 'Terraform-managed' })
        }
    }

    Invoke-Check 'azure-context' {
        $account = Invoke-AzureJson @('account', 'show')
        if ($account.id -ine $subscription -or $account.tenantId -ine $tenant) { Stop-Api2026 'Explicitly selected Azure account has the wrong tenant or subscription.' }
        @{ explicitSubscription = $subscription; tenantId = $tenant }
    }

    Invoke-Check 'resources-and-placement' {
        if (-not $ExistingResourceGroup) {
            foreach ($key in $physicalGroupKeys) { $null = Read-Resource resource_group $key -Ready }
        }
        $script:gateway = Read-Resource gateway -Ready
        $script:models = Read-Resource models -Ready
        $script:agents = Read-Resource agents -Ready
        $script:project = Read-Resource project -Ready
        $script:storage = Read-Resource storage -Ready
        $script:registry = Read-Resource registry -Ready
        foreach ($entry in @(@($models, 'models'), @($agents, 'agents'))) {
            Assert-ConfiguredValue $entry[0].properties.disableLocalAuth $true "$($entry[1]) live local authentication disabled"
        }
        Assert-ConfiguredValue $storage.properties.allowSharedKeyAccess $false 'Storage live shared keys disabled'
        foreach ($entry in @(@($gateway, $gatewayState), @($project, $projectState))) {
            if ($entry[0].identity.type -cne 'SystemAssigned' -or $entry[0].identity.tenantId -ine $tenant -or $entry[0].identity.principalId -ine $entry[1].identity[0].principal_id) {
                Stop-Api2026 'Live runtime identity does not match the selected state and tenant.'
            }
        }
        $hostName = $gateway.properties.frontend.defaultHostname
        if ([string]::IsNullOrWhiteSpace($hostName)) { Stop-Api2026 'Missing standalone gateway frontend.defaultHostname; no legacy URL fallback.' }
        $script:trustedOrigin = Get-Origin "https://$hostName"
        if ($trustedOrigin -cne $stateOrigin) { Stop-Api2026 'State gateway endpoint differs from the trusted ARM-returned gateway origin.' }
        Assert-ConfiguredValue $gateway.properties.backend $gatewayState.body.properties.backend 'gateway backend'
        foreach ($entry in @(@($models, 'models'), @($agents, 'agents'), @($storage, 'storage'), @($registry, 'registry'))) {
            $expected = (Get-StateValue $entry[1]).body
            Assert-ConfiguredValue $entry[0].sku $expected.sku "$($entry[1]) SKU"
            Assert-ConfiguredValue $entry[0].properties $expected.properties "$($entry[1]) properties"
        }
        Assert-ConfiguredValue $project.properties $projectState.body.properties 'project properties'
        foreach ($key in @('gateway', 'agents')) {
            $logs = Read-Resource logs $key -Ready
            Assert-ConfiguredValue $logs.properties (Get-StateValue logs $key).body.properties 'Log Analytics configuration'
            $insights = Read-Resource insights $key -Ready
            Assert-ConfiguredValue $insights.properties (Get-StateValue insights $key).body.properties 'Insights configuration'
            if ($insights.properties.WorkspaceResourceId -ine (Get-StateValue logs $key).id) { Stop-Api2026 'Insights points to the wrong workspace.' }
        }
        $report.gateway = @{ id = $gatewayId; origin = $trustedOrigin; apiKeyId = $keyId; apiKeyApiVersion = '2026-09-01-preview' }
        @{ groups = $physicalGroupKeys.Count; gatewaySkuOverride = 'None'; gatewayOrigin = $trustedOrigin; runtimeIdentities = 'Verified against live ARM and tenant' }
    }

    if ($PrivateLab) {
        Invoke-Check 'private-lab-configuration' -ContinueOnFailure { Test-Api2026PrivateLab }
    }

    Invoke-Check 'models-and-routes' -ContinueOnFailure {
        $provider = Read-Resource foundry_provider
        $providerExpected = (Get-StateValue foundry_provider).body.properties
        Assert-ConfiguredValue $provider.properties $providerExpected 'model provider'
        Assert-KeylessProvider $provider.properties.foundry.authentication
        if ((Get-Origin $provider.properties.foundry.endpoint) -cne (Get-Origin $models.properties.endpoint)) { Stop-Api2026 'Provider endpoint is not the live models account endpoint.' }
        foreach ($key in $deployments.Keys) {
            $deployment = Read-Resource model_deployment $key -Ready
            $expected = (Get-StateValue model_deployment $key).body
            Assert-ConfiguredValue $deployment.sku $expected.sku 'model deployment SKU/capacity'
            Assert-ConfiguredValue $deployment.properties.model $expected.properties.model 'model deployment version'
            Assert-ConfiguredValue $deployment.properties.raiPolicyName $expected.properties.raiPolicyName 'live backend content filter binding'
            $catalog = Read-Resource catalog_model $key
            $catalogExpected = (Get-StateValue catalog_model $key).body.properties | ConvertTo-Json -Depth 40 | ConvertFrom-Json -AsHashtable -Depth 40
            if (-not $catalog.properties.Contains('apiFormat') -and $catalogExpected.apiFormat -ceq 'OpenAIChatCompletions') {
                Assert-ConfiguredValue $catalog.properties.providerKind 'Foundry' 'catalog provider kind'
                $catalogExpected.Remove('apiFormat')
                $readbackProjections.Add(@{ resource = $catalog.id; field = 'apiFormat'; detail = 'Not returned; Foundry deployment, endpoints and ordered policies checked. Runtime remains separate.' })
            }
            Assert-ConfiguredValue $catalog.properties $catalogExpected 'catalog and ordered policies'
        }
        foreach ($key in $aliases.Keys) {
            $alias = Read-Resource model_alias $key
            Assert-ConfiguredValue $alias.properties (Get-StateValue model_alias $key).body.properties 'alias and ordered backends'
        }
        $key = Read-Resource runtime_api_key
        Assert-ConfiguredValue $key.properties (Get-StateValue runtime_api_key).body.properties 'API-key resource configuration'
        $report.aliases = @($aliases.Keys | Sort-Object | ForEach-Object {
            @{ armName = $_; aliasName = $aliases[$_].alias_name; apiFormat = $aliases[$_].api_format; endpoints = $aliases[$_].endpoints }
        })
        @{ deployments = $deployments.Count; callableAliases = $aliases.Count; policyVerification = 'Configuration only; enforcement/failover NOT TESTED' }
    }

    Invoke-Check 'backend-content-safety' -ContinueOnFailure {
        # System policies can appear in LIST even when their individual GET returns 404.
        $collectionId = "$modelsId/raiPolicies"
        $policyId = "$collectionId/Microsoft.DefaultV2"
        Assert-AllowedId $policyId
        $nextLink = "https://management.azure.com${collectionId}?api-version=2025-04-01-preview"
        $pages = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $policyMatches = [Collections.Generic.List[object]]::new()
        while ($nextLink) {
            $pageUri = $null
            if ($nextLink -isnot [string] -or $nextLink -match '[\\\s]' -or
                -not [uri]::TryCreate($nextLink, [UriKind]::Absolute, [ref]$pageUri) -or
                $pageUri.Scheme -cne 'https' -or $pageUri.Host -ine 'management.azure.com' -or
                -not $pageUri.IsDefaultPort -or $pageUri.UserInfo -or $pageUri.Fragment -or
                $pageUri.AbsolutePath -ine $collectionId -or $pages.Count -ge 10 -or -not $pages.Add($nextLink)) {
                Stop-Api2026 'Untrusted, repeated or excessive backend content filter collection page.'
            }
            $query = [System.Web.HttpUtility]::ParseQueryString($pageUri.Query)
            if (@($query.GetValues('api-version')).Count -ne 1 -or $query['api-version'] -cne '2025-04-01-preview') {
                Stop-Api2026 'Backend content filter collection changed API version.'
            }
            $page = Invoke-AzureJson @('rest', '--method', 'get', '--url', $nextLink)
            Assert-Map $page 'backend content filter collection'
            if ($page.value -isnot [array] -or
                ($null -ne $page.nextLink -and $page.nextLink -isnot [string])) {
                Stop-Api2026 'Invalid backend content filter collection.'
            }
            foreach ($candidate in $page.value) {
                Assert-Map $candidate 'backend content filter collection entry'
                if ($candidate.id -ieq $policyId) { $policyMatches.Add($candidate) }
            }
            $nextLink = $page.nextLink
        }
        if ($policyMatches.Count -ne 1) { Stop-Api2026 'Missing or duplicate backend content filter policy.' }
        $policy = $policyMatches[0]
        Assert-Map $policy 'backend content filter response'
        if ($policy.id -ine $policyId -or $policy.type -ine 'Microsoft.CognitiveServices/accounts/raiPolicies') {
            Stop-Api2026 'ARM returned a different backend content filter.'
        }
        Assert-ConfiguredValue $policy.properties @{ mode = 'Blocking'; type = 'SystemManaged' } 'backend content filter'
        if ($policy.properties.contentFilters -isnot [array]) { Stop-Api2026 'Missing backend content filters.' }
        $requiredFilters = @(
            foreach ($category in @('Hate', 'Selfharm', 'Sexual', 'Violence')) {
                foreach ($source in @('Prompt', 'Completion')) {
                    @{ name = $category; source = $source; enabled = $true; blocking = $true; severityThreshold = 'Medium' }
                }
            }
            @{ name = 'Jailbreak'; source = 'Prompt'; enabled = $true; blocking = $true }
            @{ name = 'Protected Material Text'; source = 'Completion'; enabled = $true; blocking = $true }
            @{ name = 'Protected Material Code'; source = 'Completion'; enabled = $true; blocking = $false }
        )
        foreach ($expected in $requiredFilters) {
            $matching = @($policy.properties.contentFilters | Where-Object { $_.name -ceq $expected.name -and $_.source -ceq $expected.source })
            if ($matching.Count -ne 1) { Stop-Api2026 'Missing or duplicate required backend content filter.' }
            Assert-ConfiguredValue $matching[0] $expected 'backend content filter settings'
        }
        @{
            policy = 'Microsoft.DefaultV2'; deploymentBindings = $deployments.Count
            readback = 'Account policy list'; pages = $pages.Count
            mode = 'Blocking'; coreHarmFilters = 8; severity = 'Medium'
            scope = 'Foundry model prompts/completions, not gateway-wide or MCP protection'
            additionalControls = 'Jailbreak/text blocking and code annotation configured'
            enforcement = 'NOT TESTED'
        }
    }

    Invoke-Check 'connections' -ContinueOnFailure {
        $bindings = @(
            @{ name = 'storage_connection'; key = '' },
            @{ name = 'registry_connection'; key = '' },
            @{ name = 'project_insights_connection'; key = 'agents' }
        )
        foreach ($binding in $bindings) {
            $name = $binding.name
            $connection = Read-Resource $name $binding.key
            $expected = (Get-StateValue $name $binding.key).body.properties
            $publicFields = @{}
            foreach ($key in $expected.Keys) { if ($key -ne 'credentials') { $publicFields[$key] = $expected[$key] } }
            Assert-ConfiguredValue $connection.properties $publicFields "$name metadata/sharing"
            if ($connection.properties.credentials) {
                Assert-ConfiguredValue $connection.properties.credentials $expected.credentials "$name credentials"
            }
        }
        if ($storage.properties.primaryEndpoints.blob -cne (Get-StateValue storage_connection).body.properties.target -or
            $registry.properties.loginServer -cne (Get-StateValue registry_connection).body.properties.target) {
            Stop-Api2026 'Connection target differs from the live backing service.'
        }
        foreach ($binding in $bindings | Where-Object { $_.name -eq 'project_insights_connection' }) {
            if ((Get-StateValue $binding.name $binding.key).body.properties.credentials.key -cne $liveResources[(Get-Address insights agents)].properties.ConnectionString) {
                Stop-Api2026 'Insights connection state uses a different destination credential.'
            }
        }
        $projectInsights = $liveResources[(Get-Address project_insights_connection agents)].properties
        @{
            connections = 3
            insightsScopes = @{
                project = @{ isSharedToAll = $projectInsights.isSharedToAll; isDefaultPresent = $projectInsights.Contains('isDefault'); isDefault = $projectInsights.isDefault }
            }
            derivedDefaultSelectionProven = $false
            credentialVerification = 'Compared only when returned; never exported. Actual service authentication requires runtime proof.'
            limits = 'Exact project existence and sharing checked; derived default selection, repeat-PUT durability and cross-project isolation are not proven.'
        }
    }

    Invoke-Check 'roles' -ContinueOnFailure {
        foreach ($key in $roleExpectations.Keys) {
            $role = Read-Resource role_assignment $key
            $expected = $roleExpectations[$key]
            Assert-ConfiguredValue $role.properties @{
                scope = $expected[0]; principalId = $expected[1]; principalType = $expected[2]
                roleDefinitionId = "$prefix/providers/Microsoft.Authorization/roleDefinitions/$($expected[3])"
            } 'live exact role binding'
            if ($role.properties.condition) { Stop-Api2026 'Unexpected live role condition.' }
        }
        @{ defaultBindings = 6; configuredCallerBindings = $callerCount; configuredDeveloperBindings = $developerCount; scope = 'Exact configured resource-scoped assignments, not a subscription-wide authorization audit' }
    }

    Invoke-Check 'exporter-topology' -ContinueOnFailure {
        $exporter = Read-Resource telemetry_exporter
        $properties = $exporter.properties
        $exporterExpected = @{
            kind = 'ApplicationInsights'; payloadCapture = $false
            applicationInsights = @{ resourceId = $insightsIds.gateway }
        }
        if (-not $properties.Contains('kind')) {
            $exporterExpected.Remove('kind')
            $readbackProjections.Add(@{ resource = $exporter.id; field = 'kind'; detail = 'Not returned; Application Insights destination and capture checked. Delivery remains unproven.' })
        }
        Assert-ConfiguredValue $properties $exporterExpected 'Application Insights exporter'
        if ($properties.openTelemetry) { Stop-Api2026 'Unexpected legacy OTLP exporter configuration.' }
        $connectionString = $liveResources[(Get-Address insights gateway)].properties.ConnectionString
        if ([string]::IsNullOrWhiteSpace($connectionString) -or
            (Get-StateValue telemetry_exporter).body.properties.applicationInsights.connectionString -cne $connectionString) {
            Stop-Api2026 'Exporter state does not reference the returned gateway Insights connection string.'
        }
        if ($properties.applicationInsights.connectionString -and $properties.applicationInsights.connectionString -cne $connectionString) {
            Stop-Api2026 'Returned exporter connection string differs from the live Insights destination.'
        }
        @{ kind = 'applicationInsights'; apiVersion = '2025-09-01-preview'; payloadCapture = $false; destinationId = $insightsIds.gateway; delivery = 'NOT TESTED'; credentialVerification = $(if ($properties.applicationInsights.connectionString) { 'Returned value matched; omitted from report' } else { 'Not returned by exporter; delivery remains unproven' }) }
    }

    Invoke-Check 'tool-servers' -ContinueOnFailure {
        foreach ($key in $toolServers.Keys) {
            $toolServer = Read-Resource mcp_tool_server $key
            Assert-ConfiguredValue $toolServer.properties (Get-StateValue mcp_tool_server $key).body.properties 'MCP tool server registration'
        }
        @{ toolServers = $toolServers.Count; apiVersion = '2025-09-01-preview'; reachability = 'NOT TESTED' }
    }

    if ($null -ne $gatewayPolicyState) {
        Invoke-Check 'gateway-policies' -ContinueOnFailure {
            $liveWorkspace = Read-Resource gateway_ip_filter default -TerraformType azapi_resource_action
            Assert-Map $liveWorkspace.properties 'live gateway workspace properties'
            $livePolicies = $liveWorkspace.properties.policies
            if ($null -eq $livePolicies) { $livePolicies = @() }
            $liveFilter = Get-GatewayIpFilter $livePolicies 'live gateway'
            $stateFilter = $gatewayPolicyState.ipFilter
            if (($null -eq $liveFilter) -ne ($null -eq $stateFilter) -or ($null -ne $stateFilter -and $liveFilter.networks -cne $stateFilter.networks)) {
                Stop-Api2026 'The live gateway IP filter differs from the last applied Terraform configuration.'
            }
            @{
                scope = 'Default workspace: models and MCP tool servers'; mode = $(if ($null -ne $stateFilter) { 'Allow' } else { 'Removed' })
                cidrCount = $(if ($null -ne $stateFilter) { $stateFilter.count } else { 0 }); apiVersion = '2025-09-01-preview'
                driftDetection = 'Not automatic; compares live ARM with the last applied list'; enforcement = 'NOT TESTED'
            }
        }
    }
    $failedChecks = @($checks.Keys | Where-Object { $checks[$_].status -cne 'PASS' })
    if ($failedChecks.Count) { throw $checks[$failedChecks[0]].error }
    $report.configurationStatus = 'PASS'
}
catch {
    $message = if ($_.Exception.Message -like 'API2026: *') { $_.Exception.Message } else { 'API2026: Unexpected validation failure; raw details omitted.' }
    $report.error = $message
}
finally {
    $report.completedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    if ($canWriteReport) {
        $writer = $stream = $null
        try {
            $stream = [IO.File]::Open($ReportPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
            $writer.Write(($report | ConvertTo-Json -Depth 20))
        }
        catch { throw 'API2026: Could not create the requested report; existing evidence was not overwritten.' }
        finally {
            if ($writer) { $writer.Dispose() }
            elseif ($stream) { $stream.Dispose() }
        }
    }
}
if ($report.configurationStatus -ne 'PASS') { throw $report.error }
[pscustomobject]$report
