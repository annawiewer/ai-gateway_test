# Gateway OpenTelemetry setup

This is the **canonical monitoring procedure** for the
[shared deployment guide](../deployment.md#monitoring-setup) and approved updates.
Run it once for the selected task; do not repeat setup from another guide.
New workloads prepare the destination here, then return to their full deployment
path. Existing workloads retain their complete approved inputs and current access.

The current AI Gateway portal requires **OpenTelemetry**, the existing Application
Insights resource ID, and all three OTLP endpoints. A legacy connection-string
exporter, or merely changing its casing, does not establish this configuration.
The gateway uses its system identity with audience `https://monitor.azure.com`
and Monitoring Metrics Publisher (`3913510d-42f4-4e42-8a64-420c390055eb`) at the
**actual OTLP data collection rule (DCR)**. Payload capture stays disabled.
Agent Insights and its connection string are unchanged.

## Ownership, permissions and cost

All application resources, including both Insights components and Log Analytics
workspaces, remain in the shared application group. Enabling
`AzureMonitorWorkspaceIngestionMode` on gateway Insights can create an Azure
Monitor workspace (AMW), DCRs, data collection endpoints (DCEs) and **Azure-managed
helper groups**. The AMW default DCR/DCE can differ from the OTLP-specific pair.
These are service-owned dependencies, not additional application stacks.
Do not import, recreate or independently manage them with Terraform.

Review these side effects and ingestion/query/retention charges before enabling.
Terraform's action count does not enumerate service-created resources. Restoring
the old exporter is **not** a complete rollback: helper resources/data and costs
can remain. Deleting them or disabling OTLP needs a separately reviewed plan.

`Microsoft.Monitor`, `Microsoft.Insights` and `Microsoft.OperationalInsights` must
be registered. This sample does not register providers/features or bypass
eligibility, policy or managed-group deny assignments. Grant the one publishing
role directly on the linked DCR; do not use a nested ARM deployment in a protected
group or broaden scope to work around denial. Query operators separately need
Log Analytics query access and AMW Prometheus query access. Publisher access is
not reader access.

## Choose the current access state

**Who/where:** the workload operator, in PowerShell 7 in the approved
`samples\terraform` working directory. First complete the main guide's
[input selection](../deployment.md#compose-the-inputs) and
[platform handoff](../deployment.md#platform-handoff-before-a-plan).
Keep those variables and the authoritative workload state/backend.

Copy exactly one assignment into that same session. These arguments follow the
complete base/additional inputs and selected ownership file; only the approved
endpoint-compatibility arguments follow the access profile.

| Current state or approved new-deployment stage | Set the monitoring plan arguments |
| --- | --- |
| Intentionally public, with approved `create` ownership | `$networkArgs = @()` |
| Already Private-only | `$networkArgs = @('-var-file=profiles\private-only.tfvars.json')` |
| Gateway still public, models already private | `$networkArgs = @('-var-file=profiles\private-connectivity.tfvars.json')` |
| **New private gateway only**, with initial temporary public access explicitly approved | `$networkArgs = @('-var-file=profiles\private-connectivity.tfvars.json', '-var=models_public_network_access=Enabled')` |

The final row is bounded to the [new-deployment staging procedure](private-connectivity.md#step-2-prepare-private-connectivity-with-models-temporarily-public).
It is **not** repair/update advice for a deployed gateway, even if that gateway
is currently public. Never use it after gateway or model access has been closed.
If temporary public access is prohibited, stop: no private-from-first-create
procedure is established here.

If an existing deployment's posture is not represented above, retain its
approved inputs and resolve the maintenance procedure with its owner; do not
select a row that reopens access. The
[existing-private entry](private-connectivity.md#existing-private-deployments)
covers closure of remaining public access after private-route verification.
The ownership profile alone does not enable private networking.

## Two-stage bootstrap or legacy-exporter upgrade

Complete [current-state selection](#choose-the-current-access-state) first.
This procedure does not reset ownership to `create`, replace approved inputs
or choose a different access profile.

```powershell
foreach ($name in @('workloadVarFile', 'networkOwnershipFile', 'additionalInputArgs',
                    'endpointCompatibilityArgs', 'networkArgs', 'subscriptionId')) {
    if (-not (Get-Variable -Name $name -ErrorAction SilentlyContinue)) {
        throw "Missing $name. Complete input selection and this guide's current-state selection first."
    }
}
if (-not $networkOwnershipFile) {
    throw 'Select the approved network-ownership input file before planning.'
}
if ($null -eq $networkArgs) {
    throw 'Select the current access-state arguments; use an empty array only for the approved public case.'
}
```

Use the authoritative workload state and **all** approved input files. Keep
`private-only` for a completed private deployment. The intermediate profile
can otherwise reopen the gateway, and the temporary models-public override
must never be used after the backend has been closed. Do not use these targeted
plans as final drift/acceptance evidence. No command below should be applied
without reviewing its saved plan and service-side effects.

### Stage A: Prepare and verify the destination

Enable only the destination. If this stage has already completed and readiness
is verified for the current deployment, do not repeat its apply.

```powershell
terraform plan -input=false "-var-file=$workloadVarFile" @additionalInputArgs `
    "-var-file=$networkOwnershipFile" @networkArgs @endpointCompatibilityArgs `
    '-target=azapi_resource.insights["gateway"]' '-out=monitoring-destination.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Destination plan failed.' }
terraform show monitoring-destination.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the destination plan.' }
```

For an existing deployment this must be **one in-place gateway Insights update**,
with the same resource ID and Log Analytics association. Stop on gateway, agent,
network or other changes, especially replacement/deletion. A genuinely new,
explicitly eligible legacy deployment also creates prerequisite group/Log
Analytics resources; review those separately. Targeting cannot bypass SKU
creation restrictions.

Review the [plan checklist](../deployment.md#review-every-plan-before-apply).
**Only after approval**, apply that saved file:

```powershell
terraform apply 'monitoring-destination.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Destination apply failed; do not continue.' }
```

**Discover and verify readiness without copying generated IDs:**

```powershell
$metadata = terraform output -json gateway_monitoring
if ($LASTEXITCODE -ne 0) { throw 'Cannot read monitoring metadata.' }
$metadata = $metadata | ConvertFrom-Json
$destination = .\scripts\Get-GatewayMonitoring.ps1 `
    -SubscriptionId $subscriptionId `
    -ApplicationInsightsId $metadata.insights_id `
    -ExpectedLogAnalyticsId $metadata.log_analytics_id -WaitSeconds 120
$destination | ConvertTo-Json -Depth 5
```

This is an ARM metadata read, **not runtime telemetry proof**. It waits for
enablement, endpoints and DCR linkage, then checks
provisioning, DCR/DCE endpoint ownership, AMW and the existing Log Analytics
destination. It verifies that every linked external group is managed by this
Insights component or AMW. Unknown topology, auth failure or timeout stops the
process; nothing falls back to a guessed endpoint or a broader scope.
The wait excludes individual CLI request durations. The helper accepts
`DataCollectionRuleResourceId` or an ARM-form `DataCollectionRuleId`.
**Immutable-only linkage is not supported by this implementation**: stop and
resolve the service metadata; do not invent an ARM ID or manually edit state.
Non-Succeeded linked resources also stop the check; rerun read-only after
investigating rather than repeatedly mutating the exporter.

**Next step depends on the deployment:**

| Situation | Next action |
| --- | --- |
| New workload | Return to the main guide's selected [Public](../deployment.md#public) or [Private-only](../deployment.md#private-only) full deployment path. Do not run a targeted exporter repair as a second bootstrap. |
| Existing workload with a specifically approved exporter repair | Continue with [Stage B](#stage-b-repair-an-existing-exporter) using the same inputs and current access state. |
| Destination not ready or permissions fail | Stop and involve the monitoring/platform owner. Generated IDs, state edits and public-access changes are not fixes. |

### Stage B: Repair an existing exporter

Refresh, plan and review the exporter/role for the bounded existing-workload
repair only:

```powershell
terraform plan -input=false "-var-file=$workloadVarFile" @additionalInputArgs `
    "-var-file=$networkOwnershipFile" @networkArgs @endpointCompatibilityArgs `
    '-target=azapi_resource.telemetry_exporter' '-out=monitoring-exporter.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Exporter plan failed.' }
terraform show monitoring-exporter.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the exporter plan.' }
```

Dependencies include the publisher role and existing gateway; targeting is not
a guarantee of scope. For an existing legacy-exporter repair expect exactly one
DCR role creation and one in-place exporter update. Stop for anything else.

Only after those expected changes have been reviewed and approved:

```powershell
terraform apply 'monitoring-exporter.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Exporter apply failed.' }
```

If the service rejects changing exporter kind in place, stop and obtain specific
approval for deletion/recreation; this sample does not pre-delete or auto-retry.
For a new eligible environment use the normal full networking-path plan after
Stage A readiness, reviewing all application creations instead.

### Existing legacy exporter: immutable kind

The legacy API has returned `ValidationError` with
`Telemetry exporter kind cannot be changed after creation.` for an existing
connection-string exporter. Terraform's planned in-place update does not prove
that the service permits it. The publisher role can already have been created
before that failure; preserve the resulting state and verify the actual role.

Prepare a **new**, explicitly reviewed replacement plan rather than retrying the
failed plan, deleting resources manually, or restoring old state:

```powershell
terraform plan -input=false "-var-file=$workloadVarFile" @additionalInputArgs `
    "-var-file=$networkOwnershipFile" @networkArgs @endpointCompatibilityArgs `
    '-target=azapi_resource.telemetry_exporter' `
    '-replace=azapi_resource.telemetry_exporter' `
    '-out=monitoring-exporter-replacement.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Exporter replacement plan failed.' }
terraform show monitoring-exporter-replacement.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the replacement plan.' }
```

For a failed Stage B where the publisher already exists, require exactly one
delete/create replacement of `azapi_resource.telemetry_exporter`, with the same
name and parent, and **no other resource actions**. Recheck the destination and
publisher before explicit destructive-action approval. Only then apply the
reviewed saved plan. This does not replace the gateway or delete monitoring
storage/data. It is not atomic: the old exporter is removed first, and if
creation fails the exporter can remain absent. Stop for separately approved
recovery rather than silently retrying or rolling back.

Terraform refresh reads the real endpoints/DCR from Insights; no portal setup,
new provider or manual endpoint/ID input is required for supported metadata.
Allow propagation, then run a fresh **full**, untargeted drift plan and the
[acceptance gates](acceptance.md). Use the [optional sample-VM runner](end-to-end.md)
only when that is the selected client. A targeted repair does not fix unrelated
Private Link, HTTP 500, retained-group or drift failures.

## Delivery and portal evidence

The private acceptance runner queries **OTelSpans** and **OTelLogs** in the linked
Log Analytics workspace using W3C `TraceId`. It requires successful gateway server
spans for every test call and at least one correlated log. No log observed means
logs delivery is **unproven**, not that successful requests must always log.
Investigate source emission before changing this gate.

It queries `azure.ai_gateway.client.token.usage` at the linked AMW's Prometheus
endpoint, scoped by `microsoft.appresourceid`, `azure.ai_gateway.workspace` and
the test window. Positive fresh samples prove scoped metrics activity, **not**
an exact token total attributable only to this run. The metric query excludes
pre-window samples carried forward by Prometheus lookback. Shared concurrent
traffic still needs matching portal/backend filters and aggregation.
Do not substitute classic `requests.operation_Id`, historical traffic, exporter
existence or a screenshot of an empty chart for all three signal paths.

Live service behavior and UI delivery are still deployment-time acceptance gates;
offline fixtures alone do not prove the preview works in a subscription.

## Troubleshooting identity and delayed ingestion

An ARM `principalId`, `Succeeded` provisioning state and matching role assignments
do **not** prove that the gateway's managed identity still exists. If inference
and telemetry fail together, verify the exact principal in the correct Entra
tenant. An authorized Graph check of the active service principal, deleted items
and directory audit can distinguish a deleted identity from an access or tenant
error. A failed or unauthorized lookup alone is not proof of deletion.

Deleted managed identities cannot be restored through Graph. A confirmed orphan
requires a separately reviewed identity repair on the existing resource, followed
by replacement of its original-scope role assignments and Terraform state
reconciliation. Identity removal/re-enablement is not atomic and can affect other
dependencies, including Key Vault-backed certificates. Do not automatically reset
an identity, recreate the gateway or reuse a plan from before the identity change.

Allow **up to 30 minutes** for the DCR publisher role to propagate before treating
an ingestion `403` as a persistent failure. This is separate from destination
provisioning and from the additional time needed for accepted records to appear
in Log Analytics. After propagation, generate a fresh bounded gateway request:
older spans may no longer be retried. Check its exact trace ID, correlated logs
and fresh, resource-scoped token samples rather than relying on old traffic.

A separately authorized synthetic OTLP trace can test the destination without
changing the exporter. Require both successful submission and the exact stored
trace; a `2xx` alone proves acceptance, not query visibility. Mark synthetic data,
exclude it from gateway acceptance, and remove any temporary publishing role.
Verify real gateway traffic independently afterward.

Token counters and trace-backed call counts can recover with different historical
coverage. Compare before/after counter samples with response usage; do not assume
that the portal's selected-range token total belongs entirely to the newest test.

## Sources

- [Official exact legacy API/SKU exporter example](https://github.com/Azure-Samples/AI-Gateway/blob/1679e3137d2fe7592d2a668d77ff71550d35b69e/modules/ai-gateway/v1/ai-gateway.bicep)
- [Complete lab, including DCR-scoped publishing](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/aigw-foundry-models)
- [Portal monitoring migration release](https://ai.gateway.azure.com/docs/releases/2026-08-28)
- [Direct OTLP ingestion](https://learn.microsoft.com/azure/azure-monitor/containers/opentelemetry-protocol-ingestion)
- [AMW managed infrastructure](https://learn.microsoft.com/azure/azure-monitor/metrics/azure-monitor-workspace-manage)
- [Managed identity deletion and token caching](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/managed-identities-faq)
- [API Management managed identity lifecycle](https://learn.microsoft.com/azure/api-management/api-management-howto-use-managed-service-identity)
- [DCR publisher permissions and propagation](https://learn.microsoft.com/azure/azure-monitor/logs/tutorial-logs-ingestion-portal#assign-permissions-to-the-dcr)
