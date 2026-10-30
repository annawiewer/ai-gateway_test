# Bicep-aligned AI Gateway: API 2026 preparation

This is a **separate Terraform entry point**, not another input layer for
scenarios 01-04. It reuses the parent configuration but selects the new
`Microsoft.ApiManagement/aigateways` family and the Bicep infrastructure profile.
The existing customer examples and legacy defaults remain unchanged.

**Status: experimental code preparation.** Offline checks do not establish live
API availability, model quota, policy enforcement, telemetry delivery or network
connectivity. No live deployment or networking acceptance is implied. The
expected service rollout must be verified before a later deployment.

## What matches Bicep

The reference is the repository's [Bicep root](../../bicep/infra/main.bicep) and
[gateway module](../../bicep/infra/ai-gateway/main.bicep), as captured on
2026-10-29. [bicep-profile.json](bicep-profile.json) is the default model/routing
configuration used by this entry and by the shared module's regression tests.

| Deployment/catalog name | Foundry model | Version | GlobalStandard capacity | Gateway token limit/minute |
| --- | --- | --- | ---: | ---: |
| `gpt-latest` | `gpt-6.1-sol` | `2026-09-29` | 20 | 20,000 |
| `gpt-6-sol` | `gpt-6-sol` | `2026-09-22` | 20 | 20,000 |
| `gpt-mini-latest` | `gpt-5.4-mini` | `2026-03-17` | 200 | 200,000 |

These are pinned Bicep values, **not an assertion that the models are available
in every region/subscription**. The capacity/token relationship in this profile
is not a universal model quota conversion. GlobalStandard does not establish
EU-only processing merely because an account is in an EU region.

There are **three deployments but two aliases**:

| Alias ARM name | Callable model name | Backend order |
| --- | --- | --- |
| `primary-router` | `gpt-latest` | `gpt-latest` priority 0, `gpt-6-sol` priority 1, `gpt-mini-latest` priority 2 |
| `mini-router` | `gpt-mini-latest` | `gpt-mini-latest` priority 0 |

All default weights are 100. Weights at the same priority are relative shares,
not independent percentages. Custom aliases accept 1-30 distinct deployment
keys, integer priority 0-100 and integer weight 1-100. Their backends must share
an API format and at least one endpoint. Both default aliases support
`/openai/v1/chat/completions` and `/openai/v1/responses`.

Each model receives the Bicep policies: minute `tokenLimit`, identity-keyed
monthly `costLimit` with `id = monthly-caller-budget` and `amount = 10`, and
`contentSafety` set to `Medium` for all four categories. These are preview
gateway policies, **not an Azure billing budget or a proven invoice cap**.
Sharing one client key does not establish separate per-person budgets.
Counter behavior, pricing interpretation and enforcement still need live tests.

The infrastructure also mirrors Bicep's:

- Three populated resource groups: gateway, Foundry models, and Foundry agents.
- Consumption gateway with system-assigned identity, managed-identity Foundry
  access, a model-only account and a separate agent account/project.
- Separate gateway/agent Application Insights and Log Analytics, 30-day log
  retention, `applicationInsights` exporter and `payloadCapture = false`.
- Identity-based Storage/Registry connections, no storage shared-key access or
  public blobs, TLS 1.2, Premium Registry without admin credentials, scoped RBAC
  and no implicit developer grants.

Connection sharing follows Bicep too: the project's Registry connection sets
`isSharedToAll = true`, while the agent account's Insights connection sets it to
`false`. These choices apply only to this entry; legacy sharing is unchanged.

There is **no connector gateway** in this variant. The runtime key remains
`default`; only its resource ID is output. Optional `gateway_access_principals`
add Entra caller access without revoking API keys or changing backend identity.
This is not an Entra-only mode.

## Exact API contracts and intentional differences

| Resource | Requested API version | Basis |
| --- | --- | --- |
| `aigateways` root | `2026-09-01-preview` | Published Learn/ARM resource schema |
| Model provider, catalog models, aliases, API keys | `2026-09-01-preview` | CLI b15 generated new-family route metadata; live acceptance pending |
| Telemetry exporter | **`2025-09-01-preview`** | Existing Bicep exporter contract; no verified 2026 exporter contract found |
| Foundry, Storage, Registry, monitoring and RBAC | Existing resource-specific versions | Reused Terraform/Bicep infrastructure, not blindly date-replaced |

This is an **explicit mixed-version configuration**, not an all-2026
certification. `gateway_api_versions` exposes the actual versions to scripts.
The source Bicep itself uses the 2025 gateway API. Installed CLI b15 also pins
its actual requests to 2025 despite generated source metadata labeled 2026;
running a CLI default command is therefore not a 2026 acceptance test.

AzAPI 2.13's embedded schema does not contain `aigateways`. Schema validation
is disabled for that root and the unsupported preview child types, not for
the legacy root. The mocked plans cannot replace server-side contract checks.

The source Bicep includes unmerged upstream policy and connector-removal
changes; see its [provenance notes](../../bicep/README.md). Matching that snapshot
does not make it production-proven. Terraform retains its own deterministic
names, project labels and optional developer grants rather than adopting Bicep
resources or application state.

Unlike the Bicep reference, the AppInsights connection uses the component
**name** for `metadata.ResourceId` while retaining its full ARM ID in `target`.
This preserves a reported successful-apply/clean-plan Terraform workaround;
the original error and provider version were unavailable, so its root cause
is unconfirmed.

The new alias API exposes PATCH for updates, whereas `azapi_resource` updates
use PUT. Changed 2026 alias properties therefore request **replacement**, not
a silently assumed PATCH. Review the saved plan: replacement can temporarily
interrupt that alias. Create uses `If-None-Match: *`, and delete uses
`If-Match: *`; these are not an optimistic-concurrency guarantee against another
writer. The CLI notes that current alias create protection is not atomic.
Live create/update/delete acceptance is still required.

## Networking: prepared versus deliberately unavailable

The [published 2026 root schema](https://learn.microsoft.com/azure/templates/microsoft.apimanagement/2026-09-01-preview/aigateways)
documents `properties.backend.subnet.id`, configured **only at creation**.
The optional `gateway_backend_subnet_id` consumes an existing subnet:

| Required platform input/check | Handling |
| --- | --- |
| Full subnet resource ID | Explicit input; never inferred from the current CLI subscription |
| Delegation `Microsoft.App/environments` | Read-only check; the old `Microsoft.Web/serverFarms` delegation is rejected |
| VNet region equals gateway region | Read-only check |
| NSG, routes, address sizing, DNS/resolver and required egress | Platform-owned; must be reviewed separately before live use |

No subnet, NSG, route, resolver, private endpoint or DNS zone is created by this
entry. A backend subnet is **outbound integration, not private client ingress**.
Changing it requests gateway replacement; `prevent_destroy` blocks an accidental
replacement of an existing gateway. Plan the subnet before the first deployment.

The published schema does **not** establish writable `publicNetworkAccess`,
legacy VNet properties or the new ingress Private Link/DNS contract. This
preparation consequently does not guess those fields or reuse `Gateway`/
`privatelink.azure-api.net` from the legacy API. The parent module rejects
`enable_private_networking` with the 2026 contract. This entry also explicitly
rejects all legacy network/access/agent/client inputs, including
`gateway_public_network_access = "Disabled"` supplied on its own. Terraform's
usual undeclared-variable warning is not sufficient: ignoring those requirements
would silently deploy the public defaults. Do not remove private requirements
just to bypass this guard; legacy private profiles are not supported here.

**This is the public Bicep-style baseline, not a private-only deployment.**
Foundry and supporting-service public access remains at the Bicep defaults.
Do not deploy it where public access is prohibited. A full private-only 2026
scenario needs the released contract, corresponding code and separate
acceptance; it is not unlocked merely by waiting until the expected rollout.

## Inputs and isolated state

Use [terraform.tfvars.example](terraform.tfvars.example) to create a **new**
`terraform.tfvars` in this directory. Replace the subscription and both regions
with explicitly approved values. Model defaults need no copy/paste. Optional
`model_deployments` and `model_aliases` replace their respective complete maps;
if deployment keys change, update both together.

The parent remains the reusable implementation; **do not change its existing
customer `terraform.tfvars` to select this contract**. Never copy, migrate or
import customer/Bicep/legacy state here. The separate working directory gives
this entry separate local state, and names include the 2026 contract. For a
remote backend, use a separately approved backend/key with encryption, locking
and restricted access; never reuse an existing workload's key or `TF_DATA_DIR`.
State contains infrastructure metadata and the Insights connection string and
must remain private even though runtime API-key secrets are not output.

The legacy connector's new `[0]` address has a `moved` block, so unchanged
legacy inputs do not require connector recreation. That state-preserving move
is **not** a migration from the old gateway resource family to the new one.

## Offline checks now; live acceptance later

From `samples\terraform`, the existing runner checks both entry points and the
mocked regressions. Provider initialization may contact the Terraform registry;
it does not deploy to Azure:

```powershell
.\scripts\Test-Offline.ps1
```

Before any later live deployment, explicitly confirm tenant/subscription,
regions, preview availability, model versions/quotas, policy/public-access
approval and a new backend/state. Review the complete saved Terraform plan.
Do not turn this preparation into an unattended `apply`.

After a separately approved deployment, the shared model probe accepts this
entry's state directory and reads the actual key API version and two aliases:

```powershell
# Run from samples\terraform; live model calls incur inference charges.
.\scripts\Test-ModelAliases.ps1 -TerraformDirectory .\api2026gateway
# Optional, only after configuring and verifying Entra caller access:
.\scripts\Test-ModelAliases.ps1 -TerraformDirectory .\api2026gateway -Authentication EntraId
```

A successful alias reply alone does not prove failover, cost/content-safety
enforcement, telemetry delivery or private networking. Explicitly exercise
those acceptance gates after rollout. The legacy `Get-GatewayMonitoring.ps1`
OTLP helper and customer private-acceptance runbook certify a different
contract; do not use them to claim success for this Application Insights /
2026 profile.

Terraform prepares agent infrastructure, **not a running agent application**.
Bicep's Python agent, image builds, GitHub/MCP hooks, Toolbox and routines remain
separate application steps. No GitHub token retrieval, destructive cleanup hook
or application deployment is copied into Terraform.

Sources: [official ARM schema](https://github.com/Azure/azure-resource-manager-schemas/blob/main/schemas/2026-09-01-preview/Microsoft.ApiManagement.json),
[official CLI b15 release](https://github.com/Azure/aigateway/releases/tag/cli-v1.0.0b15),
and the local Bicep snapshot linked above.
