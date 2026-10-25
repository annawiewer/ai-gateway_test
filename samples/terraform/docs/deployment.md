# Deployment guide

[Overview and diagrams](../README.md)

## Prerequisites

Use Terraform 1.11+ (below 2.0), Azure CLI, and PowerShell 7 for the helper scripts.
Python 3 is needed for offline tests. Check model versions, capacity and hosted-agent
availability in the chosen regions, plus inherited Azure Policy, required tags and
permissions to manage resources and scoped role assignments.

This sample targets `Microsoft.ApiManagement/service` with SKU `AIGateway`.
Check availability for that exact resource contract, subscription and region;
the newer `Microsoft.ApiManagement/aigateways` resource is not a drop-in replacement.
Review Microsoft's [resource compatibility and lifecycle guidance](https://learn.microsoft.com/azure/api-management/ai-gateway-resource)
before deployment. This sample does not migrate resource types.

Register the providers used by your configuration: `Microsoft.ApiManagement`,
`Microsoft.Web`, `Microsoft.CognitiveServices`, `Microsoft.Storage`,
`Microsoft.ContainerRegistry`, `Microsoft.OperationalInsights`, `Microsoft.Insights`
and `Microsoft.Monitor`; also `Microsoft.Network` for networking, `Microsoft.Compute`
for the optional test VM, and `Microsoft.App` for private hosted agents.

Public/private routing is independent of authentication. Clients currently use a
gateway **API key**; the gateway uses its **managed identity** for model invocation.
Caller-to-gateway Entra-only authentication is not implemented here. It can be a
separately designed policy/client change later, without supplying a missing network route.

## Inputs and state

Run commands from `samples\terraform`. For a **new environment only**, copy
[terraform.tfvars.example](../terraform.tfvars.example) to `terraform.tfvars` and
set the subscription, environment name, publisher email, regions and model map.
The map keys become client-facing aliases. See [variables.tf](../variables.tf)
and [outputs.tf](../outputs.tf) for the complete input/output contract.

For an existing deployment, reuse its **authoritative state/backend and complete
input files**. Never overwrite inputs with the example, initialize a second state
against the same resources, or apply an old saved plan. State, plan files, keys and
operational evidence stay out of Git; protect remote state and its access controls.
The commands below assume approved inputs in auto-loaded `terraform.tfvars`.
If using additional `-var-file` arguments, include them on **every plan**, before
the final network profile.

```powershell
az login
az account set --subscription "<approved-subscription-id>"
terraform init
terraform fmt -check -recursive
terraform validate
```

Stop on any command failure. Review every saved plan before applying it; reject
unexpected replacement, deletion, public reopening or permission expansion.
Changing names/regions or consolidating an older multi-resource-group layout is
a migration, not a harmless update. The current sample uses one application group;
gateway OTLP can additionally create Azure-managed monitoring helper groups.

## Monitoring setup

The gateway exporter needs real OTLP endpoints and a linked DCR, discovered from
Application Insights. Do not supply guessed endpoints or copy generated IDs.
Use a two-stage setup before the full deployment plan:

```powershell
# Existing Private-only: always retain this profile.
$networkArgs = @('-var-file=profiles\private-only.tfvars.json')
# For an intentionally Public deployment only, replace the above with @().
terraform plan @networkArgs '-target=azapi_resource.insights["gateway"]' '-out=monitoring-destination.tfplan'
# Only after a successful plan and explicit review:
terraform apply monitoring-destination.tfplan

$metadata = terraform output -json gateway_monitoring
if ($LASTEXITCODE -ne 0) { throw 'Cannot read monitoring metadata.' }
$metadata = $metadata | ConvertFrom-Json
.\scripts\Get-GatewayMonitoring.ps1 `
    -SubscriptionId '<approved-subscription-id>' `
    -ApplicationInsightsId $metadata.insights_id `
    -ExpectedLogAnalyticsId $metadata.log_analytics_id -WaitSeconds 120
```

Set `$networkArgs` to the intended stage below for a new private deployment; never
drop the private profile on an existing private environment. Review targeted plans
too: they can include dependencies. The helper is read-only and checks destination
readiness, DCR/DCE ownership and the linked Log Analytics/Azure Monitor workspaces.
After it succeeds, create a **fresh full plan** for your selected path. Terraform
then configures the exporter and the gateway's publisher role on the linked DCR.

For a bounded existing-exporter repair, target `azapi_resource.telemetry_exporter`
with the same inputs. If Azure rejects an in-place exporter-kind change, stop:
replacement needs its own reviewed `-replace=azapi_resource.telemetry_exporter`
plan and explicit deletion/recreation approval. It is not atomic and must not
replace the gateway or delete monitoring data.

## Public

Use only when public gateway/model endpoints are intentional. It is the Terraform
default, **not** a required prerequisite for Private-only.

```powershell
terraform plan -out=deployment.tfplan
# Review, then apply only the successful saved plan:
terraform apply deployment.tfplan
.\scripts\Test-ModelAliases.ps1
terraform plan -detailed-exitcode
```

The probe makes billable calls to every configured chat-completions alias from
your machine. All aliases must answer; final plan exit `0` means no changes,
`1` means an error, and `2` means changes requiring review.

## Private-only

The final [private-only profile](../profiles/private-only.tfvars.json) disables
**both gateway and model public access**. Private clients reach the gateway's
private endpoint; separate gateway outbound VNet integration reaches the model
private endpoint. Private DNS, endpoint approval and working routes are all required.

For an **already private** deployment, skip temporary-public staging. Keep
`-var-file=profiles\private-only.tfvars.json` last on every full, monitoring and
drift plan. Never apply the intermediate profile to an already-disabled gateway.

For an environment **transitioning from public**, where temporary public access
is explicitly permitted, use these provisioning stages. The retained
`private-connectivity` file is an intermediate stage, **not a third deployment path**:

| Stage | Plan arguments, after all environment inputs | Required gate before continuing |
| --- | --- | --- |
| Prepare private networking | `-var-file=profiles\private-connectivity.tfvars.json -var=models_public_network_access=Enabled` | Review/apply; gateway/model remain public. Approve private endpoints and prove private DNS/inference. |
| Close model public access | `-var-file=profiles\private-connectivity.tfvars.json` | Review/apply; model disabled. Repeat the private probe. |
| Close gateway public access | `-var-file=profiles\private-only.tfvars.json` | Review/apply; both disabled. Recheck private inference and authenticated public-network rejection. |

Save each plan with `-out=<stage>.tfplan` and apply only that reviewed plan.
Do not reopen access to bypass a failure or Azure Policy. If temporary public access
is prohibited, do not use this staged procedure unchanged: validate a supported
private creation sequence first. First-create behavior is not proven by a
successful update of an existing gateway.

Wait for actual ARM provisioning completion and approved/succeeded private
connections. On an asynchronous timeout, inspect actual state before making a new
plan; an accepted update is not proof of completion. All callers, including agents
and CI, need their own private connectivity before gateway public access is closed.

Use an existing authorized private client or enable the optional billable test VM:

```hcl
enable_private_test_client         = true
private_test_client_ssh_public_key = "ssh-ed25519 <public-key-only>"
```

The VM has no public IP; the probe uses Run Command, not inbound SSH. Its runtime
role permits only gateway key retrieval at the gateway scope. The Terraform
executor additionally needs custom role-definition management and role-assignment
permissions; Contributor or role-assignment access alone is insufficient.
The test operator needs VM read, Run Command, start and deallocate permissions.

Start the VM using `terraform output -raw private_test_vm_id`, then:

```powershell
.\scripts\Test-PrivateGateway.ps1
terraform plan -var-file=profiles\private-only.tfvars.json -detailed-exitcode
```

This helper requires the sample VM. It checks private DNS and every model alias,
retrieving the gateway key only in runtime memory. The reference models support
Chat Completions, `max_tokens` and `temperature`; other API types need compatible
probes. A successful private call alone does **not** prove public access is blocked.
Deallocate the VM after testing and verify its power state.

## Optional private hosted agent

For a new private agent, enable the networking configuration **before account
creation**; it cannot simply be added to an existing agent account afterward:

```hcl
enable_private_networking   = true
enable_private_hosted_agent = true
# location must equal gateway_location for this extension.
```

Keep the final private-only profile last. The extension adds an account/project,
dedicated outbound-injection subnet, inbound Foundry private endpoint, registry
private endpoint/DNS and scoped project permissions. It reuses the gateway/model
route and monitoring. Foundry public access is disabled; ACR public access is
unchanged. DNS changes affect every client in the linked VNet.

The Foundry private endpoint is **inbound**; agent network injection is **outbound**.
The account has `prevent_destroy`; turning off the flag or changing injection
requires an approved migration. Basic agent data is platform-managed, not a
customer-owned private Storage/Cosmos DB/Search setup. This is not deny-all egress:
Entra, ARM and telemetry connectivity still need validation; no NAT/firewall or
fully private monitoring path is added.

Terraform does **not** deploy an image or agent application:

1. Read `terraform output -json private_hosted_agent` for the **new** project and
   endpoints; compatibility outputs `project_id`/`project_endpoint` refer to the
   original project. Verify account/capability-host provisioning and private DNS,
   including registry login and regional data endpoints.
2. Deploy your application from a private executor using the
   [hosted-agent/private ACR guide](https://learn.microsoft.com/azure/foundry/agents/how-to/deploy-hosted-agent-private-azure-container-registry).
   Do not reprovision Terraform-owned infrastructure through a second workflow.
   For a prebuilt image, explicitly configure image passthrough by digest rather
   than assuming a package argument suppresses builds. Scope any build/deploy
   permissions to the required resources.
3. Discover the actual deployed **runtime managed-identity object ID**. Verify
   runtime AcrPull on the exact registry separately from Terraform's project
   AcrPull. Record the owner of any role assigned outside Terraform.
4. Set `private_hosted_agent_runtime_principal_id` to that verified ID and review
   a new plan with complete inputs and the private-only profile last. This binds
   narrow gateway key retrieval; the agent still calls the gateway with an API key.
   Never persist that key in tfvars, state, logs or agent metadata. Verify both
   runtime roles again if a new agent version changes identity.

Remove only job-created temporary roles and deallocate the executor after use.
Keep the runtime-principal input on subsequent plans, or its binding can be removed.

## Acceptance and maintenance

Require fresh results in the selected environment, not screenshots from another
deployment: each alias succeeds, missing/invalid gateway keys are rejected, expected
roles/connections and private DNS are correct, and gateway/backend telemetry
correlates to the same request. For Private-only, a **valid authenticated request
from outside the private route** must receive explicit network denial; a 401,
authentication-related 403, timeout or DNS error is not equivalent.

For a hosted agent, invoke a fresh session/version and correlate its response to
successful gateway **and intended model backend** spans in `OTelSpans` by `TraceId`
and time window. Confirm gateway/model/Foundry public settings, cleanup of temporary
roles/VMs, and a no-change plan with **all** original and runtime inputs.

For the optional guarded VM-based acceptance report:

```powershell
.\scripts\Test-CustomerAcceptance.ps1 `
    -SubscriptionId '<subscription-id>' -TenantId '<tenant-id>' `
    -ResourceGroup '<deployment-resource-group>' `
    -ReportDirectory 'C:\secure\acceptance' `
    -NetworkProfile private-only -RunPrivateProbe
```

Pass any extra inputs with `-AdditionalVarFile`. This does not test hosted-agent
runtime or public network rejection. Its overall result remains blocked until a
separate authenticated portal review is recorded using the generated checklist
and `Complete-PortalAcceptance.ps1`; that validator checks evidence completeness,
not the UI itself. Never treat blocked or unexecuted checks as passed.

Run credential-free regression checks with `.\scripts\Test-Offline.ps1`.
Azure Policy can deny, modify or create related resources; inspect actual posture
and drift after remediation instead of blindly undoing enforced settings.

Model calls, Premium ACR, Storage, monitoring and optional compute incur charges.
The gateway preview has no SLA. Before cleanup, review a destroy plan, data-retention
requirements, `prevent_destroy` guards, externally managed roles and Azure-managed
monitoring groups. Destroying Terraform resources does not certify removal of all
service-managed resources or charges; do not bypass protections automatically.
