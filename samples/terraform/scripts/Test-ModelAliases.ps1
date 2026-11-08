# Sends a short chat request to every configured model alias through the gateway.
# Run from samples/terraform after a successful apply, signed in with az login.
# ApiKey needs key-read permission; EntraId needs the AI Gateway Models User role.
# Model calls incur inference charges.
# -Bounded is the opt-in API2026 context-checked, content-free evidence path.

param(
    [ValidateSet('ApiKey', 'EntraId')]
    [string]$Authentication = 'ApiKey',
    [string]$TerraformDirectory = (Split-Path $PSScriptRoot -Parent),
    [switch]$Bounded,
    [guid]$SubscriptionId,
    [guid]$TenantId,
    [string[]]$AllowedResourceGroups,
    [switch]$SingleResourceGroup,
    [switch]$ExistingResourceGroup,
    [switch]$PrivateLab,
    [string]$ExpectedPrivateEndpointSubnetNsgId,
    [string]$ExpectedBackendSubnetId,
    [ValidateSet('Enabled', 'Disabled')][string]$ExpectedBackendPublicNetworkAccess,
    [ValidateRange(1, 4096)][int]$MaxOutputTokens,
    [ValidateRange(1, 120)][int]$TimeoutSeconds,
    [guid]$RunId,
    [switch]$TestNegativeAuthentication,
    [string]$ReportPath
)

$ErrorActionPreference = "Stop"

function Get-GatewayKeyValue($Secret) {
    $candidates = @(
        $Secret.primaryKey, $Secret.properties.primaryKey,
        $Secret.primaryValue, $Secret.properties.primaryValue
        if ($Secret.target -ceq 'Primary') { $Secret.value }
        $Secret.secondaryKey, $Secret.properties.secondaryKey,
        $Secret.secondaryValue, $Secret.properties.secondaryValue
        if ($Secret.target -ceq 'Secondary') { $Secret.value }
    )
    $value = $candidates | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    if (-not $value) { throw 'Unable to retrieve the gateway key: no supported secret value (response omitted).' }
    $value
}

function Test-AuthenticationRejection([int]$Status, $Reply) {
    if ($Status -eq 401) { return $true }
    if ($Status -ne 403) { return $false }
    $code = [string]$Reply.error.code
    $message = [string]$Reply.error.message
    $code -match '^(InvalidApiKey|InvalidSubscriptionKey|InvalidAuthenticationToken|MissingAuthenticationToken|AuthenticationFailed|Unauthorized)$' -or
        $message -match '(?i)(api[- ]?key|subscription[- ]?key|authentication|bearer token|access token|invalid token|missing token|unauthorized)'
}

$boundedArguments = @('SubscriptionId', 'TenantId', 'AllowedResourceGroups', 'SingleResourceGroup', 'ExistingResourceGroup', 'PrivateLab', 'ExpectedPrivateEndpointSubnetNsgId', 'ExpectedBackendSubnetId', 'ExpectedBackendPublicNetworkAccess', 'MaxOutputTokens', 'TimeoutSeconds', 'RunId', 'TestNegativeAuthentication', 'ReportPath')
if (-not $Bounded -and @($boundedArguments | Where-Object { $PSBoundParameters.ContainsKey($_) }).Count) {
    throw 'Bounded probe arguments require -Bounded; legacy probe defaults were not changed.'
}
if ($Bounded) {
    foreach ($required in @('TerraformDirectory', 'SubscriptionId', 'TenantId', 'AllowedResourceGroups', 'MaxOutputTokens', 'TimeoutSeconds')) {
        if (-not $PSBoundParameters.ContainsKey($required)) { throw "Bounded probes require explicit -$required." }
    }
    if ($RunId -eq [guid]::Empty) { $RunId = [guid]::NewGuid() }
    if ($ReportPath) {
        $ReportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportPath)
        if ((Test-Path -LiteralPath $ReportPath) -or -not (Test-Path -LiteralPath (Split-Path $ReportPath -Parent) -PathType Container)) {
            throw 'Choose a new report file in an existing directory; previous evidence is never overwritten.'
        }
    }
    $requests = [Collections.Generic.List[object]]::new()
    $report = [ordered]@{
        schemaVersion = 2
        contract = 'api2026gateway'
        scope = 'Bounded chat completions and the selected credential mode only.'
        overallStatus = 'INCOMPLETE'
        runId = $RunId.ToString()
        startedUtc = [DateTimeOffset]::UtcNow.ToString('o')
        status = 'FAIL'
        authentication = $Authentication
        maxOutputTokens = $MaxOutputTokens
        outputTokenField = 'max_completion_tokens'
        timeoutSeconds = $TimeoutSeconds
        timeoutScope = 'Request timeout; on PowerShell 7.4+ the same value also bounds stalled response reads. DNS may exceed a short nominal timeout.'
        requests = $requests
        negativeAuthentication = @{ status = 'NOT TESTED'; scope = 'Missing and synthetic-invalid credentials only; a valid but ungranted identity is NOT TESTED.' }
        telemetryDelivery = @{ status = 'NOT TESTED'; detail = 'Run/trace IDs identify client requests only; delivery schema and server-side correlation support must be verified separately.' }
        failoverAndPolicyEnforcement = @{ status = 'NOT TESTED' }
        toolServerReachability = @{ status = 'NOT TESTED'; detail = 'The probe calls model aliases only; MCP tool servers are not called.' }
        responsesApi = @{ status = 'NOT TESTED' }
    }
    $apiKey = $accessToken = $headers = $secretJson = $secret = $reply = $body = $null
    try {
        $backendArguments = @{}
        foreach ($name in @('SingleResourceGroup', 'ExistingResourceGroup', 'PrivateLab', 'ExpectedPrivateEndpointSubnetNsgId', 'ExpectedBackendSubnetId', 'ExpectedBackendPublicNetworkAccess')) {
            if ($PSBoundParameters.ContainsKey($name)) { $backendArguments[$name] = $PSBoundParameters[$name] }
        }
        $context = & (Join-Path $PSScriptRoot 'Test-Api2026Deployment.ps1') `
            -TerraformDirectory $TerraformDirectory -SubscriptionId $SubscriptionId -TenantId $TenantId `
            -AllowedResourceGroups $AllowedResourceGroups @backendArguments
        if ($context.configurationStatus -cne 'PASS') { throw 'PROBE: Configuration acceptance did not pass.' }
        foreach ($target in $context.aliases) {
            if ($target.apiFormat -cne 'OpenAIChatCompletions' -or '/openai/v1/chat/completions' -cnotin $target.endpoints) {
                throw 'PROBE: Unsupported alias API; no credentials or inference requested.'
            }
        }
        $report.gatewayOrigin = $context.gateway.origin
        $report.configurationStatus = $context.configurationStatus
        if ($Authentication -eq 'EntraId') {
            $accessToken = & az account get-access-token --subscription $SubscriptionId.ToString() `
                --resource https://azure-api.net/aigateway --query accessToken --output tsv --only-show-errors 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($accessToken -join "`n"))) {
                throw 'PROBE: Unable to acquire the selected AI Gateway Entra token; no API-key fallback.'
            }
            $headers = @{ Authorization = "Bearer $accessToken" }
        }
        else {
            $secretJson = & az rest --method post --subscription $SubscriptionId.ToString() `
                --url "https://management.azure.com$($context.gateway.apiKeyId)/listSecrets?api-version=$($context.gateway.apiKeyApiVersion)" `
                --output json --only-show-errors 2>$null
            if ($LASTEXITCODE -ne 0) { throw 'PROBE: Unable to retrieve the selected gateway key; response omitted.' }
            try { $secret = ($secretJson -join "`n") | ConvertFrom-Json }
            catch { throw 'PROBE: Invalid key envelope; response omitted.' }
            $apiKey = Get-GatewayKeyValue $secret
            $headers = @{ Authorization = "Bearer $apiKey" }
        }
        $cases = @($context.aliases | ForEach-Object { @{ target = $_; credential = 'valid' } })
        if ($TestNegativeAuthentication) {
            $cases += @{ target = $context.aliases[0]; credential = 'missing' }
            $cases += @{ target = $context.aliases[0]; credential = 'invalid' }
        }
        foreach ($case in $cases) {
            $traceId = [guid]::NewGuid().ToString('N')
            $requestHeaders = @{
                traceparent = "00-$traceId-$([guid]::NewGuid().ToString('N').Substring(0, 16))-01"
                'x-ms-client-request-id' = $RunId.ToString()
            }
            if ($case.credential -eq 'valid') {
                foreach ($name in $headers.Keys) { $requestHeaders[$name] = $headers[$name] }
            }
            elseif ($case.credential -eq 'invalid') {
                if ($Authentication -eq 'EntraId') { $requestHeaders.Authorization = 'Bearer synthetic-invalid-token' }
                else { $requestHeaders.Authorization = 'Bearer synthetic-invalid-api-key' }
            }
            $body = @{
                model = $case.target.aliasName
                messages = @(@{ role = 'user'; content = 'Reply with exactly OK.' })
                stream = $false
                max_completion_tokens = $MaxOutputTokens
            } | ConvertTo-Json -Depth 5
            $entry = [ordered]@{
                alias = $case.target.aliasName
                credentialCase = $case.credential
                traceId = $traceId
                status = 'FAIL'
            }
            $requests.Add($entry)
            $httpStatus = 0
            $readTimeout = @{}
            if ((Get-Command Microsoft.PowerShell.Utility\Invoke-RestMethod).Parameters.ContainsKey('OperationTimeoutSeconds')) {
                $readTimeout.OperationTimeoutSeconds = $TimeoutSeconds
            }
            try {
                $reply = Invoke-RestMethod -Method Post `
                    -Uri "$($context.gateway.origin)/default/models/openai/v1/chat/completions" `
                    -Headers $requestHeaders -ContentType 'application/json' -Body $body `
                    -TimeoutSec $TimeoutSeconds @readTimeout -MaximumRedirection 0 -MaximumRetryCount 0 `
                    -SkipCertificateCheck:$false -SkipHttpErrorCheck -StatusCodeVariable httpStatus
            }
            catch { throw 'PROBE: HTTP request failed or exceeded its timeout; response omitted and not retried.' }
            $entry.httpStatus = [int]$httpStatus
            if ($case.credential -eq 'valid') {
                if ($httpStatus -ne 200 -or -not $reply.choices -or [string]::IsNullOrWhiteSpace($reply.choices[0].message.content)) {
                    throw "PROBE: Authenticated chat completion was not proven (HTTP $httpStatus); response omitted."
                }
                $entry.usage = @{}
                foreach ($name in @('prompt_tokens', 'completion_tokens', 'total_tokens')) {
                    $value = $reply.usage.$name
                    if (($value -is [int] -or $value -is [long]) -and $value -ge 0) { $entry.usage[$name] = $value }
                }
                if ($entry.usage.completion_tokens -gt $MaxOutputTokens) { throw 'PROBE: Reported completion usage exceeded the explicit output cap; no retry attempted.' }
                $entry.result = 'Chat text returned; content omitted'
            }
            else {
                if (-not (Test-AuthenticationRejection $httpStatus $reply)) {
                    throw "PROBE: Authentication rejection was not established (HTTP $httpStatus); a generic 403/network denial is not proof."
                }
                $entry.result = 'Authentication rejection classified; response omitted'
            }
            $entry.status = 'PASS'
        }
        if ($TestNegativeAuthentication) { $report.negativeAuthentication.status = 'PASS' }
        $report.status = 'PASS'
    }
    catch {
        $report.error = if ($_.Exception.Message -like 'PROBE: *' -or $_.Exception.Message -like 'API2026: *' -or
            $_.Exception.Message -eq 'Unable to retrieve the gateway key: no supported secret value (response omitted).') {
            $_.Exception.Message
        }
        else { 'PROBE: Validation or credential acquisition failed; raw details omitted.' }
    }
    finally {
        $apiKey = $accessToken = $headers = $requestHeaders = $secretJson = $secret = $reply = $body = $null
        $report.completedUtc = [DateTimeOffset]::UtcNow.ToString('o')
        if ($ReportPath) {
            $writer = $stream = $null
            try {
                $stream = [IO.File]::Open($ReportPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
                $writer.Write(($report | ConvertTo-Json -Depth 20))
            }
            catch { throw 'PROBE: Could not create the requested report; existing evidence was not overwritten.' }
            finally {
                if ($writer) { $writer.Dispose() }
                elseif ($stream) { $stream.Dispose() }
            }
        }
    }
    if ($report.status -ne 'PASS') { throw $report.error }
    [pscustomobject]$report
    return
}

$root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TerraformDirectory)
$outputsJson = & terraform "-chdir=$root" output -json
if ($LASTEXITCODE -ne 0) { throw "Cannot read Terraform outputs." }
$outputs = $outputsJson | ConvertFrom-Json
$gatewayUrl = ([string]$outputs.gateway_endpoint.value).TrimEnd('/')
$keyId = $outputs.gateway_api_key_id.value
$isNewFamily = $outputs.gateway_contract.value.resource_type -eq 'Microsoft.ApiManagement/aigateways' -or
    $keyId -match '/Microsoft\.ApiManagement/aigateways/'
if ($Authentication -eq 'ApiKey' -and !$keyId) {
    throw "Gateway API key resource ID is missing."
}

$versionsOutput = $outputs.PSObject.Properties['gateway_api_versions']
if ($null -ne $versionsOutput) {
    $keyApiVersion = [string]$versionsOutput.Value.value.api_keys
}
elseif ($isNewFamily) { throw 'Missing gateway_api_versions for the standalone gateway; refusing to infer its contract.' }
else { $keyApiVersion = '2025-09-01-preview' }
if ($keyApiVersion -notin @('2025-09-01-preview', '2026-09-01-preview')) {
    throw 'Missing or unsupported API-key management version in gateway_api_versions.'
}

$aliasOutput = $outputs.PSObject.Properties['model_alias_configuration']
if ($null -ne $aliasOutput) {
    if ($aliasOutput.Value.value -isnot [pscustomobject]) { throw 'Invalid model_alias_configuration output.' }
    $targets = @($aliasOutput.Value.value.PSObject.Properties | ForEach-Object { $_.Value })
}
else {
    if ($isNewFamily) { throw 'Missing model_alias_configuration for the new gateway; deployment names are not an alias list.' }
    $modelApis = $outputs.model_api_configuration.value
    if (-not $modelApis) {
        throw "Missing model_api_configuration output. Review and apply the output update with your existing inputs/profile before testing."
    }
    $targets = @($outputs.model_deployment_ids.value.PSObject.Properties.Name | ForEach-Object {
        [pscustomobject]@{
            alias_name = $_
            api_format = $modelApis.PSObject.Properties[$_].Value.api_format
            endpoints  = $modelApis.PSObject.Properties[$_].Value.endpoints
        }
    })
}
$modelNames = @($targets | ForEach-Object { $_.alias_name })
if (!$gatewayUrl -or $modelNames.Count -eq 0 -or
    @($modelNames | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) }).Count -or
    @($modelNames | Sort-Object -Unique).Count -ne $modelNames.Count) {
    throw "Gateway endpoint or model aliases are missing, invalid or duplicated."
}
foreach ($api in $targets) {
    $model = $api.alias_name
    if ($api.api_format -cne 'OpenAIChatCompletions' -or
        @($api.endpoints) -cnotcontains '/openai/v1/chat/completions') {
        throw "Unsupported probe API for ${model}: requires OpenAIChatCompletions and /openai/v1/chat/completions. Use a model-specific test; this is not a network failure."
    }
}

$apiKey = $null
$accessToken = $null
try {
    if ($Authentication -eq 'EntraId') {
        $accessToken = az account get-access-token `
            --resource https://azure-api.net/aigateway `
            --query accessToken --output tsv --only-show-errors
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($accessToken)) {
            throw "Unable to acquire an AI Gateway Entra token. Check your Azure CLI login and tenant; no API-key fallback is attempted."
        }
        $headers = @{ Authorization = "Bearer $accessToken" }
    }
    else {
        $secretJson = az rest --method post `
            --url "https://management.azure.com${keyId}/listSecrets?api-version=$keyApiVersion" `
            --output json --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to retrieve the gateway key. Check your Azure identity and permissions."
        }
        try { $secret = ($secretJson -join "`n") | ConvertFrom-Json }
        catch { throw 'Unable to retrieve the gateway key: invalid secret envelope (response omitted).' }
        $apiKey = Get-GatewayKeyValue $secret
        $headers = if ($isNewFamily) { @{ Authorization = "Bearer $apiKey" } } else { @{ 'Api-Key' = $apiKey } }
    }

    foreach ($model in $modelNames) {
        $body = @{
            model    = $model
            messages = @(@{ role = "user"; content = "Say hello in one short sentence." })
        } | ConvertTo-Json -Depth 5

        $reply = Invoke-RestMethod -Method Post `
            -Uri "$gatewayUrl/default/models/openai/v1/chat/completions" `
            -Headers $headers -ContentType "application/json" -Body $body

        if (!$reply.choices -or !$reply.choices[0].message.content) {
            throw "No chat-completion text returned for alias '$model'."
        }
        "{0}: {1}" -f $model, $reply.choices[0].message.content
    }
}
finally {
    $apiKey = $null
    $accessToken = $null
    $headers = $null
    $secretJson = $null
    $secret = $null
    $candidates = $null
}
