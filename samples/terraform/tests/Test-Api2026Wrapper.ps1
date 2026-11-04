#Requires -Version 7.0
param([switch]$AllTests)
$ErrorActionPreference = 'Stop'
$root = Join-Path (Split-Path $PSScriptRoot -Parent) 'api2026gateway'
$arguments = @("-chdir=$root", 'test', '-verbose', '-json')
if (-not $AllTests) {
    foreach ($file in @('integration.tftest.hcl', 'private-lab.tftest.hcl')) {
        $arguments += "-filter=$(Join-Path 'tests' $file)"
    }
}
$lines = & terraform @arguments
$exitCode = $LASTEXITCODE
$messages = @($lines | ForEach-Object { ConvertFrom-Json $_ -AsHashtable -Depth 100 })
if ($exitCode -ne 0) {
    foreach ($message in $messages | Where-Object { $_.type -eq 'diagnostic' }) {
        Write-Host "$($message.diagnostic.summary): $($message.diagnostic.detail)"
    }
    throw 'Provider-mocked API wrapper tests failed.'
}
$plans = @($messages | Where-Object { $_.type -eq 'test_plan' -and $_.'@testfile' -match '(integration|private-lab)\.tftest\.hcl$' })
if ($plans.Count -ne 4) { throw 'Expected the two existing and two opt-in real-wrapper integration plans.' }
$profile = Get-Content -LiteralPath (Join-Path $root 'model-profile.json') -Raw | ConvertFrom-Json -AsHashtable
foreach ($message in $plans) {
    $resources = @{}
    foreach ($change in $message.test_plan.resource_changes | Where-Object { $_.mode -eq 'managed' }) {
        $resources[$change.address] = $change.change.after
    }
    $gateway = $resources['module.gateway.azapi_resource.gateway']
    if ($gateway.type -cne 'Microsoft.ApiManagement/aigateways@2026-09-01-preview' -or
        $gateway.body.ContainsKey('sku') -or
        $gateway.tags.'gateway-contract' -cne 'api2026gateway') {
        throw 'Wrapper contract selection/tag forwarding did not reach the child resource.'
    }
    $roles = @($resources.Keys | Where-Object { $_ -like 'module.gateway.azapi_resource.role_assignment*' })
    $projectInsights = $resources['module.gateway.azapi_resource.project_insights_connection["agents"]']
    if (@($resources.Keys | Where-Object { $_ -like 'module.gateway.azapi_resource.insights_connection*' }).Count -ne 0 -or
        $projectInsights.type -cne 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' -or
        $projectInsights.body.properties.isSharedToAll -ne $false -or
        $projectInsights.body.properties.metadata.ApiType -cne 'Azure' -or
        $projectInsights.body.properties.ContainsKey('isDefault') -or
        $projectInsights.body.properties.ContainsKey('sharedUserList')) {
        throw 'Wrapper must create only the unshared project Insights connection, without an inherited account connection or unsupported inputs.'
    }
    $privateLab = $message.'@testrun' -eq 'private_lab_profile_reaches_child_with_computed_ids'
    $privateBackends = $message.'@testrun' -eq 'explicit_inputs_reach_child' -or $privateLab
    $expectedAccess = if ($privateBackends) { 'Disabled' } else { 'Enabled' }
    foreach ($name in @('models', 'agents', 'storage', 'registry')) {
        if ($resources["module.gateway.azapi_resource.$name"].body.properties.publicNetworkAccess -cne $expectedAccess) {
            throw "Backend access was not forwarded to the real $name resource."
        }
    }
    foreach ($name in @('models', 'agents')) {
        if ($resources["module.gateway.azapi_resource.$name"].body.properties.allowProjectManagement -ne $true -or
            $resources["module.gateway.azapi_resource.$name"].body.properties.disableLocalAuth -ne $true) {
            throw "API2026 must retain project management and disable local authentication on the $name account."
        }
    }
    $authentication = $resources['module.gateway.azapi_resource.foundry_provider'].body.properties.foundry.authentication
    if ($authentication.kind -cne 'ManagedIdentity' -or
        $authentication.managedIdentity.resource -cne 'https://cognitiveservices.azure.com/' -or
        $resources['module.gateway.azapi_resource.storage'].body.properties.allowSharedKeyAccess -ne $false) {
        throw 'Wrapper must retain the backend MI audience and disabled Storage shared keys.'
    }
    foreach ($kind in @('logs', 'insights')) {
        foreach ($name in @('gateway', 'agents')) {
            $properties = $resources['module.gateway.azapi_resource.' + $kind + '["' + $name + '"]'].body.properties
            foreach ($flag in @('publicNetworkAccessForIngestion', 'publicNetworkAccessForQuery')) {
                if (($privateBackends -and $properties[$flag] -cne 'Disabled') -or
                    (-not $privateBackends -and $properties.ContainsKey($flag))) {
                    throw 'Monitoring must forward explicit backend disablement without changing the unspecified baseline.'
                }
            }
        }
    }
    if ($message.'@testrun' -eq 'default_profile_reaches_child') {
        if ($resources.Count -ne 33 -or $roles.Count -ne 6 -or $gateway.body.properties.Count -ne 0) { throw 'Default wrapper must plan the full public 33-resource/six-role sample with project-only Insights.' }
        foreach ($name in $profile.model_deployments.Keys) {
            $model = $profile.model_deployments[$name]
            $deployment = $resources['module.gateway.azapi_resource.model_deployment["' + $name + '"]']
            if ($deployment.body.properties.model.name -cne $model.model_name -or
                $deployment.body.properties.model.version -cne $model.model_version -or
                $deployment.body.properties.raiPolicyName -cne 'Microsoft.DefaultV2' -or
                $deployment.body.sku.capacity -ne $model.capacity) {
                throw 'Default model name/version/capacity or backend safety binding did not reach the real child module.'
            }
            $catalog = $resources['module.gateway.azapi_resource.catalog_model["' + $name + '"]']
            if ($catalog.body.properties.policies.Count -ne 3 -or
                $catalog.body.properties.policies[2].type -cne 'requestRateLimit' -or
                $catalog.body.properties.policies[2].callsPerPeriod -ne $model.request_limit) {
                throw 'The default request policy did not reach the real child module.'
            }
        }
    }
    elseif ($message.'@testrun' -eq 'explicit_inputs_reach_child') {
        $model = $resources['module.gateway.azapi_resource.model_deployment["custom-model"]']
        $catalog = $resources['module.gateway.azapi_resource.catalog_model["custom-model"]']
        $caller = $resources['module.gateway.azapi_resource.role_assignment["gateway-models-user-fixture"]']
        if ($resources.Count -ne 36 -or $roles.Count -ne 14 -or
            $model.body.properties.model.name -cne 'gpt-5.4-mini' -or $model.body.properties.model.version -cne '2026-03-17' -or
            $model.body.sku.capacity -ne 7 -or $catalog.body.properties.policies[0].count -ne 700 -or
            $catalog.body.properties.policies[1].amount -ne 3 -or
            $catalog.body.properties.policies[2].type -cne 'requestRateLimit' -or
            $catalog.body.properties.policies[2].callsPerPeriod -ne 17 -or
            $catalog.body.properties.policies[2].periodSeconds -ne 60 -or
            $catalog.body.properties.policies.Count -ne 4 -or
            $catalog.body.properties.policies[3].type -cne 'ipFilter' -or
            $catalog.body.properties.policies[3].action -cne 'Allow' -or
            ($catalog.body.properties.policies[3].cidrRanges -join ',') -cne '2001:db8:1234::/48,203.0.113.42/32' -or
            $model.body.properties.raiPolicyName -cne 'Microsoft.DefaultV2' -or
            $gateway.body.properties.backend.subnet.id -notlike '*/virtualNetworks/shared/subnets/backend' -or
            $gateway.tags.fixture -cne 'forwarded' -or
            $caller.body.properties.principalId -cne '00000000-0000-0000-0000-000000000004' -or
            $caller.body.properties.principalType -cne 'ServicePrincipal' -or $caller.parent_id -ine $gateway.id) {
            throw 'Explicit models, policies, subnet, tags or scoped runtime caller were not forwarded.'
        }
        $developers = @($roles | Where-Object { $_ -match '\["developer-' })
        if ($developers.Count -ne 7) { throw 'Explicit developer principal must produce its seven configured grants.' }
        foreach ($address in $developers) {
            if ($resources[$address].body.properties.principalId -cne '00000000-0000-0000-0000-000000000005' -or
                $resources[$address].body.properties.principalType -cne 'Group') {
                throw 'Explicit developer principal/type was not forwarded.'
            }
        }
    }
    elseif ($message.'@testrun' -eq 'single_group_profile_reaches_child' -or $privateLab) {
        $groupAddresses = @($resources.Keys | Where-Object { $_ -like 'module.gateway.azapi_resource.resource_group*' })
        if ($groupAddresses.Count -ne 1 -or $groupAddresses[0] -cne 'module.gateway.azapi_resource.resource_group["gateway"]' -or
            $resources[$groupAddresses[0]].name -cne 'single-fixture') {
            throw 'Single-group opt-in must have exactly the original gateway RG address owning the requested name.'
        }
        if (-not $privateLab) {
            if ($resources.Count -ne 31 -or $roles.Count -ne 6 -or $gateway.body.properties.Count -ne 0) {
                throw 'Single-RG public mode must retain the default workload minus the two surplus group owners.'
            }
        }
        else {
            $privateCounts = @{
                api2026_vnet = 1; api2026_nsg = 2; api2026_nat_ip = 1; api2026_nat = 1
                api2026_subnet = 3; api2026_ampls = 1; api2026_monitor_resource = 4
                api2026_private_endpoint = 5; api2026_dns_zone = 9; api2026_dns_group = 5; api2026_dns_link = 9
                api2026_identity = 2; api2026_nic = 1; api2026_vm = 1; api2026_container = 1
                api2026_client_grant = 11; api2026_blob_read_diagnostics = 1
            }
            if ($resources.Count -ne 90 -or $roles.Count -ne 6 -or
                -not $resources.ContainsKey('module.gateway.azapi_update_resource.disk_access["client"]')) {
                throw 'Private mode must plan the exact 90-resource graph, including its native disk restriction and project-only Insights.'
            }
            foreach ($name in $privateCounts.Keys) {
                if (@($resources.Keys | Where-Object { $_.StartsWith("module.gateway.azapi_resource.$name[", [StringComparison]::Ordinal) }).Count -ne $privateCounts[$name]) {
                    throw "Unexpected private-lab resource count: $name."
                }
            }
            if (@($message.test_plan.resource_changes | Where-Object { $_.mode -eq 'data' }).Count -ne 0) {
                throw 'The owned private graph must not read an external/historical foundation.'
            }
            $gatewayChange = @($message.test_plan.resource_changes | Where-Object { $_.address -ceq 'module.gateway.azapi_resource.gateway' })[0]
            if ($gatewayChange.change.after_unknown.body.properties.backend.subnet.id -ne $true -or
                $gateway.body.properties.ContainsKey('publicNetworkAccess')) {
                throw 'The new subnet ID must remain computed in the creation body without an invented gateway ingress flag.'
            }
            foreach ($key in @('positive', 'negative')) {
                $identityChange = @($message.test_plan.resource_changes | Where-Object { $_.address -ceq "module.gateway.azapi_resource.api2026_identity[`"$key`"]" })[0]
                if ($identityChange.change.after_unknown.id -ne $true -or $identityChange.change.after_unknown.output -ne $true) {
                    throw 'The full private graph must plan before fresh identity IDs are available.'
                }
            }
            $storage = $resources['module.gateway.azapi_resource.storage']
            if ($storage.body.properties.networkAcls.bypass -cne 'None' -or $storage.ignore_body_changes) {
                throw 'Fresh private labs must not inherit the historical trusted-service/resource-instance overlay.'
            }
        }
    }
    else { throw 'Unexpected integration run.' }
}
$summary = @($messages | Where-Object { $_.type -eq 'test_summary' })[-1].test_summary
if ($summary.passed -lt 4) { throw 'Expected nonzero selected wrapper tests, including all four integration plans.' }
"API wrapper checks passed ($($summary.passed) Terraform runs; 4 nested-plan integration inspections; mocked provider only)."
