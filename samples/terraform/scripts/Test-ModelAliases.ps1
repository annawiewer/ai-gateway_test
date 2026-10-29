# Sends a short chat request to every configured model alias through the gateway.
# Run from samples/terraform after a successful apply, signed in with az login.
# ApiKey needs key-read permission; EntraId needs the AI Gateway Models User role.
# Model calls incur inference charges.

param(
    [ValidateSet('ApiKey', 'EntraId')]
    [string]$Authentication = 'ApiKey',
    [string]$TerraformDirectory = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"

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
elseif ($isNewFamily) { throw 'Missing gateway_api_versions for the new gateway; refusing a silent 2025 fallback.' }
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
        $candidates = @(
            $secret.primaryKey, $secret.properties.primaryKey,
            $secret.primaryValue, $secret.properties.primaryValue
            if ($secret.target -ceq 'Primary') { $secret.value }
            $secret.secondaryKey, $secret.properties.secondaryKey,
            $secret.secondaryValue, $secret.properties.secondaryValue
            if ($secret.target -ceq 'Secondary') { $secret.value }
        )
        $apiKey = $candidates | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
        if (-not $apiKey) { throw 'Unable to retrieve the gateway key: no supported secret value (response omitted).' }
        $headers = @{ "Api-Key" = $apiKey }
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
