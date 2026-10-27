# Customer acceptance for an existing deployment

Use this after the chosen [networking path](../README.md#choose-your-networking-path)
has been applied successfully. It is **not** a new-deployment or recovery guide.
The [legacy-resource limitation](reference.md#resource-type-and-lifecycle) remains.
An isolated Sweden Central rehearsal on October 27, 2026 created the original
`service` / `AIGateway` through Terraform and closed public access in stages.
Private model calls, authentication controls, public network rejections,
telemetry, central firewall routing and four independent no-change plans passed.
This does not prove private-from-first-create or another customer's policies,
CI/backend or region. The October 25
[private-agent proof](private-hosted-agent.md#observed-deployment-and-proof)
is separate; no hosted-agent application ran in the October 27 rehearsal.

The blocks below address the base gateway/model/project deployment. They do
not automatically select or verify the optional private agent. Use its
`private_hosted_agent` output and the
[separate runtime/identity checks](private-hosted-agent.md#repeatable-operation-after-deployment)
for new private agent deployments.

**Automated private-profile entrypoint:** follow the [end-to-end runbook](end-to-end.md)
and `scripts\Test-CustomerAcceptance.ps1` for executable checks, sanitized reports,
same-private-route negative authentication, correlated telemetry and a separate
portal/metrics review. The detailed blocks below cover the manual route, including an
**existing private client without the sample VM**, and the public path.
Do not run them as a second billable test by default after a successful VM run.

For an **existing private client**, use the
[two-terminal handoff](private-connectivity.md#test-from-an-existing-private-client):
**A** runs Steps 1-3, Step 4's control-plane checks and Steps 6-7; **B** runs only
the trace-aware requests, Step 5 and the sanitized evidence export. Keep A's full
`$o` outputs in A. B receives a small metadata subset, never Terraform/backend
access. Staging calls alone do not complete final private-only acceptance.

Otherwise run the appropriate blocks in order in one PowerShell **7** session.
A starts in `samples\terraform`, or in the authoritative Terragrunt workload unit.
Retain the original inputs/backend; the notes below identify Terragrunt command
substitutions. Do not print raw state, ARM responses, credentials, keys or
telemetry connection strings. These checks do not grant permissions or repair
resources. Inference is billable.

## 1. Confirm the target and read live resource identities

Restore the main guide's [approved context and complete inputs](../deployment.md#compose-the-inputs)
first, including any runtime files and endpoint compatibility arguments.
The operator needs
resource/role-assignment read access and permission to query the gateway's
Log Analytics workspace and linked AMW Prometheus endpoint. Running the private probe also requires the
[test-client permissions](private-connectivity.md#test-client-permissions).

```powershell
$ErrorActionPreference = 'Stop'
foreach ($name in @('subscriptionId', 'tenantId', 'customerVarFile', 'networkOwnershipFile',
                    'additionalInputArgs', 'endpointCompatibilityArgs')) {
    if (-not (Get-Variable -Name $name -ErrorAction SilentlyContinue)) {
        throw "Missing $name. Restore the main guide's approved context and input selection."
    }
}
$subscription = $subscriptionId
$tenant = $tenantId
$accountJson = az account show --output json --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the approved Azure context.' }
$account = $accountJson | ConvertFrom-Json
if ($account.id -ne $subscription -or $account.tenantId -ne $tenant) {
    throw 'Subscription/tenant mismatch. Stop; do not change context automatically.'
}
$outputJson = terraform output -json
if ($LASTEXITCODE -ne 0) { throw 'Cannot read deployment outputs.' }
$o = $outputJson | ConvertFrom-Json
$outputJson = $null
$sampleDirectory = Read-Host 'Absolute path to the approved samples\terraform source folder'
if (-not [IO.Path]::IsPathFullyQualified($sampleDirectory) -or
    -not (Test-Path -LiteralPath (Join-Path $sampleDirectory 'scripts\Get-GatewayMonitoring.ps1') -PathType Leaf)) {
    throw 'Select the approved source folder, not a Terragrunt cache or a new backend.'
}

function Read-ArmUrl([string]$Url) {
    $prefix = "https://management.azure.com/subscriptions/$subscription/"
    if (-not $Url.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Unexpected ARM read scope.'
    }
    $json = az rest --subscription $subscription --method get --url $Url --output json --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'ARM read failed; acceptance is incomplete.' }
    $json | ConvertFrom-Json -Depth 50
}
function Get-Arm([string]$Id, [string]$Version) {
    Read-ArmUrl "https://management.azure.com${Id}?api-version=$Version"
}
function Get-ArmItems([string]$Id, [string]$Version) {
    $url = "https://management.azure.com${Id}?api-version=$Version"
    while ($url) {
        $page = Read-ArmUrl $url
        $page.value
        $url = $page.nextLink
    }
}

$gatewayId = [string]$o.gateway_id.value
$modelsId = [string]$o.foundry_models_id.value
$projectId = [string]$o.project_id.value
$agentsId = $projectId -replace '/projects/[^/]+$', ''
$agentsGroup = "/subscriptions/$subscription/resourceGroups/$($o.resource_groups.value.agents)"
$storageId = "$agentsGroup/providers/Microsoft.Storage/storageAccounts/$($o.storage_account_name.value)"
$registryName = ([string]$o.container_registry_endpoint.value).Split('.')[0]
$registryId = "$agentsGroup/providers/Microsoft.ContainerRegistry/registries/$registryName"
$gateway = Get-Arm $gatewayId '2025-09-01-preview'
$models = Get-Arm $modelsId '2025-04-01-preview'
$agents = Get-Arm $agentsId '2025-04-01-preview'
$project = Get-Arm $projectId '2025-04-01-preview'
$storage = Get-Arm $storageId '2024-01-01'
$registry = Get-Arm $registryId '2023-07-01'
foreach ($resource in @($gateway, $models, $agents, $project, $storage, $registry)) {
    if ($resource.properties.provisioningState -ne 'Succeeded') {
        throw "Resource is not ready: $($resource.id)"
    }
}
foreach ($resource in @($gateway, $project)) {
    if (-not $resource.identity.principalId -or $resource.identity.tenantId -ne $tenant) {
        throw "Missing or wrong-tenant managed identity: $($resource.id)"
    }
}
'Target resources and runtime principal IDs verified.'
```

**Expected:** the final message. A `404`, access denial, failed provisioning or
missing identity is a failure, not permission to recreate a resource.
For Terragrunt, replace only `terraform output -json` above with
`terragrunt run --log-level error --tf-forward-stdout -- output -json`.
Run it in the already configured workload unit, not the sample source directory.
After a profile change, repeat Step 1 so the live resource objects are current.

## 2. Verify the six exact service role bindings

Compare **current live identities**, resource scopes and role-definition IDs.
Do not substitute an old principal ID, accept an assignment on the wrong
resource, or count unrelated/inherited roles as proof of the configured binding.

```powershell
$bindings = @(
    @{ name = 'gateway-foundry-user'; principal = $gateway.identity.principalId; scope = $modelsId; role = '53ca6127-db72-4b80-b1b0-d745d6d5456d' }
    @{ name = 'project-storage'; principal = $project.identity.principalId; scope = $storageId; role = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' }
    @{ name = 'project-acr-pull'; principal = $project.identity.principalId; scope = $registryId; role = '7f951dda-4ed3-4680-a7ca-43fe172d538d' }
    @{ name = 'project-contributor'; principal = $project.identity.principalId; scope = $agentsId; role = '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68' }
    @{ name = 'project-openai-user'; principal = $project.identity.principalId; scope = $agentsId; role = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' }
    @{ name = 'project-user'; principal = $project.identity.principalId; scope = $agentsId; role = 'a97b65f3-24c7-4388-baec-2e87135dc908' }
)
foreach ($binding in $bindings) {
    $roleId = "/subscriptions/$subscription/providers/Microsoft.Authorization/roleDefinitions/$($binding.role)"
    $assignments = @(Get-ArmItems "$($binding.scope)/providers/Microsoft.Authorization/roleAssignments" '2022-04-01')
    $match = @($assignments | Where-Object {
        $_.properties.scope -ieq $binding.scope -and
        $_.properties.principalId -eq $binding.principal -and
        $_.properties.principalType -eq 'ServicePrincipal' -and
        $_.properties.roleDefinitionId -ieq $roleId -and
        -not $_.properties.condition
    })
    if ($match.Count -ne 1) { throw "Expected exactly one configured binding: $($binding.name)" }
    "$($binding.name): verified"
}
```

**Expected:** six `verified` lines. Optional developer roles are additional and
must be reviewed against the explicitly approved `developer_principal_id` and
`rbac.tf`; their existence does not replace these six bindings. The optional VM's
key-reader binding is separate: inspect its gateway-scoped assignment and custom
role in **Gateway > Access control (IAM)** using the scope/action table in the
[private guide](private-connectivity.md#test-client-permissions). The private probe
also exercises that VM identity's ability to retrieve the key.

## 3. Verify the Foundry connections and gateway backend

```powershell
$projectConnections = @(Get-ArmItems "$projectId/connections" '2025-04-01-preview')
$accountConnections = @(Get-ArmItems "$agentsId/connections" '2025-06-01')
$expectedConnections = @(
    @{ name = $storage.name; items = $projectConnections; category = 'AzureStorageAccount'; auth = 'AAD'; target = $storage.properties.primaryEndpoints.blob; resource = $storageId }
    @{ name = "$($registry.name)-conn"; items = $projectConnections; category = 'ContainerRegistry'; auth = 'ManagedIdentity'; target = $registry.properties.loginServer; resource = $registryId }
    @{ name = ([string]$o.application_insights_ids.value.agents).Split('/')[-1]; items = $accountConnections; category = 'AppInsights'; auth = 'ApiKey'; target = $o.application_insights_ids.value.agents; resource = $o.application_insights_ids.value.agents }
)
foreach ($expected in $expectedConnections) {
    $match = @($expected.items | Where-Object {
        $_.name -eq $expected.name -and
        $_.properties.category -eq $expected.category -and
        $_.properties.authType -eq $expected.auth -and
        $_.properties.target -eq $expected.target -and
        $_.properties.metadata.ResourceId -ieq $expected.resource
    })
    if ($match.Count -ne 1) { throw "Missing or incorrect connection: $($expected.name)" }
    "$($expected.name): target/authentication metadata verified"
}
$provider = Get-Arm "$gatewayId/workspaces/default/modelProviders/foundry" '2025-09-01-preview'
$foundry = $provider.properties.foundry
if ($foundry.authentication.kind -ne 'ManagedIdentity' -or
    $foundry.authentication.managedIdentity.resource -ne 'https://cognitiveservices.azure.com/' -or
    @($foundry.resourceIds).Count -ne 1 -or $foundry.resourceIds[0] -ine $modelsId -or
    ([string]$foundry.endpoint).TrimEnd('/') -ne ([string]$models.properties.endpoint).TrimEnd('/')) {
    throw 'Incorrect gateway-to-model backend/authentication.'
}
'Gateway model provider verified.'
```

**Expected:** three connection confirmations and the provider confirmation.
This verifies configuration metadata, **not** credential contents, Storage
object access, an ACR image pull or running hosted agents. The sample deploys no
agent/image. If agent execution is a customer requirement, require a separate
approved image-pull, artifact-access and agent-execution test before signing off;
do not label these checks as an agent-runtime pass.

## 4. Exercise every alias on the intended route

Check [probe compatibility](reference.md#probe-compatibility) first. Record the
UTC start/end times and the per-alias results without keys or prompts containing
customer data.

Choose the client before making calls:

| Approved route | Run here |
| --- | --- |
| Private, sample VM | The [owned VM power cycle](private-connectivity.md#test-with-the-optional-sample-vm). Its report already includes per-alias trace IDs and same-route negative-key checks. Do not duplicate the manual request blocks below. |
| Private, existing client without the sample VM | First the [exact endpoint-IP DNS checks](private-connectivity.md#test-from-an-existing-private-client), then the trace-aware request block below **on that same private client**. |
| Intentionally public | The trace-aware request block below on the approved public client. Skip only the private-posture/DNS checks, not roles, authentication or telemetry. |

On **A**, for **either private client**, first verify the live model account still has
`publicNetworkAccess = Disabled` and `networkAcls.defaultAction = Deny`; the
gateway must match the explicitly selected profile. Both private endpoints must report
`Succeeded` and `Approved`:

```powershell
$networkProfile = 'private-only'
$selectedProfile = Get-Content -LiteralPath (Join-Path $sampleDirectory "profiles\$networkProfile.tfvars.json") -Raw | ConvertFrom-Json
if ($models.properties.publicNetworkAccess -ne 'Disabled' -or
    $models.properties.networkAcls.defaultAction -ne 'Deny' -or
    $gateway.properties.publicNetworkAccess -ne $selectedProfile.gateway_public_network_access -or
    $gateway.properties.virtualNetworkType -ne 'External' -or
    -not $gateway.properties.virtualNetworkConfiguration.subnetResourceId) {
    throw 'Live network posture does not match the current private profile.'
}
foreach ($name in @('gateway', 'models')) {
    $endpoint = Get-Arm $o.private_endpoint_ids.value.$name '2024-05-01'
    $connections = @(
        @($endpoint.properties.privateLinkServiceConnections) +
        @($endpoint.properties.manualPrivateLinkServiceConnections) |
            Where-Object { $null -ne $_ }
    )
    $target = if ($name -eq 'gateway') { $gatewayId } else { $modelsId }
    if ($endpoint.properties.provisioningState -ne 'Succeeded' -or
        $connections.Count -ne 1 -or
        $connections[0].properties.privateLinkServiceConnectionState.status -ne 'Approved' -or
        $connections[0].properties.privateLinkServiceId -ine $target) {
        throw "Private endpoint is not ready or targets the wrong resource: $name"
    }
}
```

For the VM path, set `$testStartUtc = [DateTimeOffset]::UtcNow` immediately before
its power-cycle/probe block and `$testEndUtc = [DateTimeOffset]::UtcNow` after it.
Require `"passed": true`, every alias HTTP `200`/`OK`, same-route negative checks
and confirmed deallocation. Retain the report's per-call trace IDs, then skip
to Step 6. Failure still requires the
[VM cleanup procedure](private-connectivity.md#step-6-stop-the-vm-when-you-are-done).

### Trace-aware calls from the selected existing client

This block uses **API-key authentication**, matching the reference's key-based
checks. The approved identity needs gateway key-read permission; do not grant
it automatically or change an intentionally different authentication design.
The key is retrieved into memory, never pasted into a command or file.
Do not enable command tracing, verbose HTTP logging or transcripts that capture
headers. Calls are billable: one bounded request per compatible alias, no retries.
For the two-terminal route, this block runs on **B**, after the approved metadata
import and DNS checks. Do not run Steps 1-3 on B to populate these variables.

```powershell
$manualPositiveControl = $false
$requestEvidence = @()
$gatewayUrl = ([string]$o.gateway_endpoint.value).TrimEnd('/')
$keyId = [string]$o.gateway_api_key_id.value
$aliases = @($o.model_deployment_ids.value.PSObject.Properties.Name)
if (-not $gatewayUrl -or -not $keyId -or $aliases.Count -eq 0) {
    throw 'Missing endpoint, key resource ID or aliases.'
}
if (-not $o.model_api_configuration.value) {
    throw 'Missing model API metadata. Review the output update before testing.'
}
foreach ($alias in $aliases) {
    $api = $o.model_api_configuration.value.PSObject.Properties[$alias].Value
    if ($api.api_format -cne 'OpenAIChatCompletions' -or
        @($api.endpoints) -cnotcontains '/openai/v1/chat/completions') {
        throw "Unsupported API for $alias. Use the approved model-specific test."
    }
}
$testStartUtc = [DateTimeOffset]::UtcNow
$apiKey = $null
$headers = $null
try {
    $apiKey = az rest --subscription $subscription --method post `
        --url "https://management.azure.com${keyId}/listSecrets?api-version=2025-09-01-preview" `
        --query primaryKey --output tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($apiKey)) {
        throw 'Cannot retrieve the approved gateway key.'
    }
    foreach ($alias in $aliases) {
        $traceId = [guid]::NewGuid().ToString('N')
        $spanId = [guid]::NewGuid().ToString('N').Substring(0, 16)
        $headers = @{ 'Api-Key' = $apiKey; traceparent = "00-$traceId-$spanId-01" }
        $body = @{
            model = $alias
            messages = @(@{ role = 'user'; content = 'Reply with exactly OK and no other text.' })
            max_tokens = 8
            temperature = 0
        } | ConvertTo-Json -Depth 5
        $response = Invoke-WebRequest -Method Post `
            -Uri "$gatewayUrl/default/models/openai/v1/chat/completions" `
            -Headers $headers -ContentType 'application/json' -Body $body `
            -SkipHttpErrorCheck -MaximumRedirection 0 -TimeoutSec 90
        if ([int]$response.StatusCode -ne 200) {
            throw "Positive control failed for $alias, HTTP $($response.StatusCode)."
        }
        $reply = $response.Content | ConvertFrom-Json
        if (-not $reply.choices -or ([string]$reply.choices[0].message.content).Trim() -cne 'OK') {
            throw "Expected OK from $alias; do not interpret this as an authentication pass."
        }
        $requestEvidence += [pscustomobject]@{
            alias = $alias; traceId = $traceId; httpStatus = 200; response = 'OK'
        }
    }
    $manualPositiveControl = $true
}
finally {
    $testEndUtc = [DateTimeOffset]::UtcNow
    $apiKey = $null
    $headers = $null
    $response = $null
    $reply = $null
}
$requestEvidence | ConvertTo-Json -Depth 4
```

**Expected:** one sanitized record per alias with HTTP `200`, `OK` and a unique
32-character trace ID. Retain these records and the UTC bounds in the restricted
evidence location. The reference models support `max_tokens` and `temperature`;
other request types need their own approved probe. A generic
`Test-ModelAliases.ps1` reply alone does not supply these trace IDs.
Do not run a public-path infrastructure plan against a private deployment.

## 5. Reject missing and invalid runtime keys

Skip this block if the VM report already passed both negative tests.
Otherwise run it **on the same selected client and same route** immediately
after the successful trace-aware controls above. For private-only deployments,
that means the private client, **not** the operator's disconnected laptop.
No public endpoint needs to be opened for authentication testing.

```powershell
if (-not $manualPositiveControl) { throw 'A fresh same-route valid-key control is required first.' }
$gatewayUrl = ([string]$o.gateway_endpoint.value).TrimEnd('/')
$alias = @($o.model_deployment_ids.value.PSObject.Properties.Name)[0]
$body = @{ model = $alias; messages = @(@{ role = 'user'; content = 'Say OK.' }); max_tokens = 8; temperature = 0 } |
    ConvertTo-Json -Depth 5
$negativeEvidence = @()
foreach ($case in @(
    @{ name = 'missing-key'; headers = @{} },
    @{ name = 'invalid-key'; headers = @{ 'Api-Key' = 'intentionally-invalid-acceptance-key' } }
)) {
    $traceId = [guid]::NewGuid().ToString('N')
    $spanId = [guid]::NewGuid().ToString('N').Substring(0, 16)
    $case.headers.traceparent = "00-$traceId-$spanId-01"
    $response = Invoke-WebRequest -Method Post `
        -Uri "$gatewayUrl/default/models/openai/v1/chat/completions" `
        -Headers $case.headers -ContentType 'application/json' -Body $body `
        -SkipHttpErrorCheck -MaximumRedirection 0 -TimeoutSec 90
    $status = [int]$response.StatusCode
    $authenticationSpecific = [string]$response.Content -match 'api[- _]?key|subscription.?key|unauthori[sz]ed|authentication|credentials'
    $networkSpecific = [string]$response.Content -match 'public.?network|public.?access|virtual.?network|firewall|private.?endpoint'
    $response = $null
    if ($status -notin @(401, 403) -or -not $authenticationSpecific -or $networkSpecific) {
        throw "Authentication rejection not verified: $($case.name), HTTP $status"
    }
    $negativeEvidence += [pscustomobject]@{
        name = $case.name; traceId = $traceId; httpStatus = $status
        authenticationSpecific = $authenticationSpecific; networkSpecific = $networkSpecific
    }
}
$testEndUtc = [DateTimeOffset]::UtcNow
$negativeEvidence | ConvertTo-Json -Depth 4
```

**Expected:** two records with `401` or `403`, `authenticationSpecific: true` and
`networkSpecific: false`. The check classifies the response in memory without
exporting it. Unrecognized wording requires local investigation and is **not**
an automatic pass. A successful valid-key control on the **same path**, followed by both
rejections, is required. DNS/TLS/timeouts, redirects, `404`, `429`, or a generic
network `403` do **not** pass this check. If this route cannot be exercised, record
it as **not verified**. Do not switch to a different route or use a previously successful
VM call as the positive control for a laptop's request. Do not copy runtime keys into commands,
reports or screenshots.

### Return existing-client evidence to the deployment host

Only for the two-terminal route. On **B**, after both request blocks succeed,
export this sanitized report to its approved restricted folder. It contains no
request/response body, credential, state or full outputs.

```powershell
if (-not $clientHandoff -or -not $manualPositiveControl -or
    @($requestEvidence).Count -ne $aliases.Count -or @($negativeEvidence).Count -ne 2 -or
    @($dnsEvidence).Count -ne @($clientHandoff.dnsTargets).Count) {
    throw 'Incomplete current-run client evidence; do not export an acceptance pass.'
}
$clientResult = [ordered]@{
    schemaVersion = 1
    runId = $clientHandoff.runId
    stage = $clientHandoff.stage
    subscriptionId = $subscription
    tenantId = $tenant
    gatewayId = $o.gateway_id.value
    metadataSha256 = (Get-FileHash -LiteralPath $handoffFile -Algorithm SHA256).Hash
    testStartUtc = $testStartUtc.ToString('o')
    testEndUtc = $testEndUtc.ToString('o')
    dns = $dnsEvidence
    requests = $requestEvidence
    negativeRequests = $negativeEvidence
}
$evidenceDirectory = Read-Host 'Absolute path to B''s existing restricted evidence folder outside the checkout'
if (-not [IO.Path]::IsPathFullyQualified($evidenceDirectory) -or
    -not (Test-Path -LiteralPath $evidenceDirectory -PathType Container)) {
    throw 'Use an existing, approved restricted folder.'
}
$clientResultFile = Join-Path $evidenceDirectory "private-client-result-$($clientHandoff.runId).json"
$clientResult | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $clientResultFile -Encoding utf8NoBOM
Get-FileHash -LiteralPath $clientResultFile -Algorithm SHA256
```

Transfer only this report back to **A**, with its SHA256 confirmed separately.
Keep A's original metadata file and `$clientHandoff`; do **not** replace A's full
`$o` with B's subset. Final acceptance requires the latest `private-only` run:

```powershell
$clientResultFile = Read-Host 'Full path to the returned sanitized client report'
$expectedHash = (Read-Host 'Report SHA256 confirmed by the client owner').Trim()
if ((Get-FileHash -LiteralPath $clientResultFile -Algorithm SHA256).Hash -ine $expectedHash) {
    throw 'Client report hash mismatch.'
}
$clientResult = Get-Content -LiteralPath $clientResultFile -Raw | ConvertFrom-Json
if ($clientResult.schemaVersion -ne 1 -or $clientResult.runId -cne $clientHandoff.runId -or
    $clientResult.stage -cne 'private-only' -or $clientHandoff.stage -cne 'private-only' -or
    $clientResult.subscriptionId -ine $subscription -or $clientResult.tenantId -ine $tenant -or
    $clientResult.gatewayId -ine $o.gateway_id.value -or
    $clientResult.metadataSha256 -ine (Get-FileHash -LiteralPath $handoffFile -Algorithm SHA256).Hash) {
    throw 'Report does not belong to this approved final-stage handoff and deployment.'
}
$requestEvidence = @($clientResult.requests)
$expectedAliases = @($o.model_deployment_ids.value.PSObject.Properties.Name)
if ($requestEvidence.Count -ne $expectedAliases.Count -or
    @($clientResult.negativeRequests).Count -ne 2) { throw 'Incomplete client request evidence.' }
foreach ($alias in $expectedAliases) {
    $match = @($requestEvidence | Where-Object {
        $_.alias -ceq $alias -and $_.httpStatus -eq 200 -and $_.response -ceq 'OK' -and
        $_.traceId -cmatch '^[0-9a-f]{32}$'
    })
    if ($match.Count -ne 1) { throw "Missing successful traced request: $alias" }
}
foreach ($name in @('missing-key', 'invalid-key')) {
    $match = @($clientResult.negativeRequests | Where-Object {
        $_.name -ceq $name -and $_.httpStatus -in @(401, 403) -and
        $_.authenticationSpecific -eq $true -and $_.networkSpecific -eq $false -and
        $_.traceId -cmatch '^[0-9a-f]{32}$'
    })
    if ($match.Count -ne 1) { throw "Missing authentication-specific rejection: $name" }
}
foreach ($target in $clientHandoff.dnsTargets) {
    $match = @($clientResult.dns | Where-Object {
        $_.name -ceq $target.name -and $_.hostname -ieq ([uri]$target.url).DnsSafeHost
    })
    if ($match.Count -ne 1 -or @($match[0].addresses).Count -eq 0 -or
        @($match[0].addresses | Where-Object { $_ -notin @($target.expectedIps) }).Count) {
        throw "Missing exact endpoint-IP evidence: $($target.name)"
    }
}
$testStartUtc = [DateTimeOffset]::Parse($clientResult.testStartUtc)
$testEndUtc = [DateTimeOffset]::Parse($clientResult.testEndUtc)
$handoffTime = [DateTimeOffset]::Parse($clientHandoff.capturedAtUtc)
if ($testStartUtc -lt $handoffTime.AddMinutes(-1) -or
    $testStartUtc -gt $handoffTime.AddMinutes(30) -or $testEndUtc -lt $testStartUtc -or
    $testEndUtc -gt [DateTimeOffset]::UtcNow.AddMinutes(1)) {
    throw 'Invalid or stale client test window.'
}
'Client evidence matched. Continue live telemetry and drift verification on A.'
```

The report is **not** a substitute for Azure telemetry or a public-boundary
test. The live rehearsal used an independent Windows PowerShell 5.1/managed-
identity client. These customer blocks use PowerShell 7/Azure CLI; the exact
snippets were not live-executed in that rehearsal.

## 6. Verify telemetry delivery, not just exporter existence

Complete [OTLP setup](monitoring.md) first. Keep the six service role checks above;
the DCR publishing role below is an additional, narrowly scoped assignment.

```powershell
$destination = & (Join-Path $sampleDirectory 'scripts\Get-GatewayMonitoring.ps1') -SubscriptionId $subscription `
    -ApplicationInsightsId $o.application_insights_ids.value.gateway `
    -ExpectedLogAnalyticsId $o.gateway_monitoring.value.log_analytics_id
$exporter = Get-Arm "$gatewayId/workspaces/default/telemetryExporters/appinsights" '2025-09-01-preview'
if ($exporter.properties.kind -ne 'OpenTelemetry' -or
    $exporter.properties.payloadCapture -ne $false -or
    $exporter.properties.applicationInsights.resourceId -ine $destination.insightsId -or
    $exporter.properties.openTelemetry.credentials.managedIdentity.resource -cne 'https://monitor.azure.com') {
    throw 'Incorrect telemetry exporter target or payload-capture setting.'
}
foreach ($name in @('metricsEndpoint', 'logsEndpoint', 'tracesEndpoint')) {
    if ($exporter.properties.openTelemetry.$name -cne $destination.endpoints[$name]) { throw "Incorrect $name." }
}
$publishing = @(Get-ArmItems "$($destination.dataCollectionRuleId)/providers/Microsoft.Authorization/roleAssignments" '2022-04-01' |
    Where-Object {
        $_.properties.scope -ieq $destination.dataCollectionRuleId -and
        $_.properties.principalId -eq $gateway.identity.principalId -and
        $_.properties.principalType -eq 'ServicePrincipal' -and -not $_.properties.condition -and
        $_.properties.roleDefinitionId -ieq "/subscriptions/$subscription/providers/Microsoft.Authorization/roleDefinitions/3913510d-42f4-4e42-8a64-420c390055eb"
    })
if ($publishing.Count -ne 1) { throw 'Exact DCR publishing role not verified.' }
$destination.logAnalyticsId
$testStartUtc.ToString('o')
$testEndUtc.ToString('o')
```

Open **that gateway Log Analytics workspace > Logs** (not agent insights).
Allow several minutes for ingestion; replace the time bounds and trace IDs below
with the VM report's trace IDs or the existing client's `$requestEvidence`
values. Copy the actual `$testStartUtc` and `$testEndUtc` values from the preceding
block, not the example dates. The automated runner additionally enforces
successful gateway server-span status and scoped Prometheus metrics.

```kusto
union withsource=TelemetryTable OTelSpans, OTelLogs
| where TimeGenerated between (datetime(2026-01-01T12:00:00Z) .. datetime(2026-01-01T12:15:00Z))
| where TraceId in ("<first-probe-trace-id>", "<second-probe-trace-id>")
| project TimeGenerated, TelemetryTable, TraceId
| order by TimeGenerated asc
```

**Expected:** new gateway request/related telemetry attributable to the test
window and model requests. Require each positive trace's successful gateway
Server span (HTTP 200, default workspace, models route) and correlated OTelLogs,
not merely any row sharing a trace ID. Inspect trace IDs and
available alias/path dimensions locally to distinguish unrelated concurrent
traffic. Do not export full `customDimensions`, request/response bodies or
credentials. If the preview emits a different schema, use the resource's actual
tables and record that schema; a query error, empty result, or exporter existence
alone is **not** proof of delivery. Do not enable payload capture to troubleshoot
this acceptance check. Retest after ingestion delay; unresolved delivery is an
open acceptance item, not a silent pass.

Also verify fresh `azure.ai_gateway.client.token.usage` through the destination's
Prometheus endpoint, with the same Insights/workspace/time filters as the portal.
Use the query and interpretation in the [automated runbook](end-to-end.md):
positive metric samples are not an exact token total for just your calls.

## 7. Finish with a drift check and explicit acceptance record

For a private deployment:

Run this on **A**, not B. With plain Terraform:

```powershell
terraform plan -input=false "-var-file=$customerVarFile" @additionalInputArgs `
    "-var-file=$networkOwnershipFile" "-var-file=$sampleDirectory\profiles\$networkProfile.tfvars.json" `
    @endpointCompatibilityArgs -detailed-exitcode
switch ($LASTEXITCODE) {
    0 { 'No pending Terraform changes.' }
    1 { throw 'Plan failed; acceptance is incomplete.' }
    2 { throw 'Pending changes require review; do not apply automatically.' }
    default { throw 'Unexpected Terraform exit code.' }
}
```

For Terragrunt, run `terragrunt run -- plan -input=false -detailed-exitcode` in
the authoritative workload unit, then use the same exit-code check. First
confirm that unit still passes the complete approved input files and final
private-only profile; do not append a second conflicting input selection.
The platform and DNS owners must also run their own full refreshed no-change
plans. Include a separate runtime-access unit if that owns the existing client's
grant. Workload no-change alone does not prove independent foundations unchanged.

For an intentionally public deployment, omit **only** the private `-var-file`
argument, retaining all its usual approved inputs/backend. Never omit it for a
private deployment. Keep plan output protected because it can contain secrets.

Record subscription/tenant, resource IDs, timestamp, Git revision, selected
profile, aliases tested, six service bindings plus the DCR publishing role, connection metadata, authentication
statuses, telemetry evidence, drift exit code and VM power state. Mark every item
**passed**, **failed** or **not verified**; do not include keys or raw state.

Acceptance remains limited to the demonstrated gateway/model route. Explicitly
record the expected/observed gateway public access, not a hardcoded public
assumption. For private-only ingress, require a new positive private call per
alias and a valid-credential public request rejected specifically by the network
boundary. Use an approved client outside the private network, record its DNS/
network context and the actual response without credentials. A 401,
authentication-specific 403, DNS error or timeout alone is insufficient.

The automated runner does not perform this public-boundary test. Nor does
disabled gateway ingress imply a private Foundry hosted-agent network or change
API-key clients to Entra. Record any required hosted-agent/image/artifact tests
separately. Undemonstrated customer requirements remain **unmet**, even when
the selected configuration and private backend checks pass.
