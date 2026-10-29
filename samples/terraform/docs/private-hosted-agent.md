# Private hosted-agent deployment reference

**Optional, not a prerequisite for the gateway.** Follow the
[step-by-step deployment guide](../01-04-deployment.md#start-here) first. Use this guide
only when an application owner has approved a new private agent account and its
separate application deployment. HCL/JSON blocks are file contents; PowerShell
commands run in the approved workload directory.

> **Live path verified on October 25, 2026.** An additional VNet-injected
> account/project ran the existing hosted-agent image successfully through the
> private gateway. Terraform prepares infrastructure; application deployment
> and the acceptance checks below remain separate requirements for each environment.

## Observed deployment and proof

In that historical lab configuration, the additive deployment created 14
infrastructure resources without changing or
replacing existing managed resources, followed by one separately reviewed
Terraform assignment for the new runtime's narrow gateway key-reader role.
The original account, agent, gateway and model deployments were retained.

- The new account, project capability host and private endpoints provisioned
  successfully. Foundry, ACR login/data and gateway DNS resolved privately from
  the VNet deployment client.
- A separate hosted-agent version reused the existing image by immutable digest,
  without a build. A fresh Responses request returned **OK**.
- The exact request trace contained gateway **HTTP 200** and model-backend
  **HTTP 200** spans. An authenticated request over the gateway's public address
  returned **HTTP 403: public network access disabled**.
- Gateway, model account and new Foundry account kept public access disabled.
  The temporary deployment VM was deallocated, its three temporary scoped roles
  removed and its pre-existing roles preserved. The final Terraform plan had
  no changes.

The runtime still uses managed identity to retrieve the gateway key from ARM,
then sends that key to the gateway. Gateway-to-model authentication remains
managed identity. This is **not** proof of caller-to-gateway Entra token
authentication or universally private control-plane/telemetry traffic.
This single deployment is not a guarantee for other regions or policy settings.
This count is historical; use your reviewed plan to determine the resources
for your selected ownership mode and inputs.

## Configure new agent accounts from the start

Use this guide for new private agent deployments, not as a requirement to
migrate an existing test agent. Changing authentication does not create a private route. Foundry Hosted Agent
network injection must be configured when the account is created; it cannot be
added to the existing account.

The optional `enable_private_hosted_agent = true` extension creates an additional
Basic Foundry account/project using either a sample-created agent subnet
(`create`) or an approved existing subnet (`existing`). It follows Microsoft's
[Basic VNet sample](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-terraform/11-private-network-basic-vnet)
and [networking options](https://learn.microsoft.com/azure/foundry/agents/concepts/networking-options).
Basic uses **Azure-managed, multitenant data resources**, not separately provisioned
Cosmos DB, AI Search or Storage. Choose a different Standard setup if agent data
must reside in data resources you own.

The verified reference path is:

```text
Private deployment client -> new Foundry private endpoint -> hosted agent
Hosted agent -> dedicated delegated subnet -> existing gateway private endpoint
             -> existing private model backend
```

The Foundry private endpoint is for inbound access. The separately configured
network injection is what supplies agent outbound connectivity.

See the [private-agent topology and current authentication sequence](architecture.md#3-private-agent-reference).
Enable the private extension when preparing the **new agent account** so its
network configuration is present at creation. Application deployment and the
actual runtime-identity binding still follow infrastructure creation; this is
not a one-command agent deployment. The base public defaults remain unchanged.
This extension reuses the gateway; it does not change its resource type or SKU.
See the [resource contract](reference.md#resource-type-and-lifecycle) when
preparing a new environment.

VNet injection does not move Basic's data into separately provisioned data
resources or guarantee network isolation. Also verify the preview agent
invocation endpoint separately: account public-access settings alone are not
proof of private-only hosted-agent ingress.

## Resource changes

| Component | `create` ownership | `existing` ownership |
| --- | --- | --- |
| Account/project ending in `-private`, Basic capability host | New workload resources | Same new workload resources; original account/project/models remain |
| Dedicated agent integration subnet | New `agents` subnet, index 3 of the sample /16, delegated to `Microsoft.App/environments` | Supply `existing_private_network.agent_subnet_id`; no subnet change |
| Agent network controls | Sample NSG with HTTPS allows for Entra ID, ARM, ACR and Monitor | Your platform team retains NSG/UDR/firewall ownership and supplies the required routes |
| Foundry private endpoint | New endpoint and workload zone group using sample zones | New endpoint in `endpoint_subnet_ids.agents`; supplied Cognitive Services/OpenAI/services zones, chosen zone-group owner |
| ACR private endpoint | New endpoint plus `privatelink.azurecr.io` zone/link/group | New endpoint in `endpoint_subnet_ids.registry`; supply `private_dns_zone_ids.registry`, keep central zone/link ownership |
| Roles and connections | New project AcrPull, optional developer roles, existing registry/Insights connections | Same workload roles/connections; original identities/roles remain untouched |

Both modes reuse the Premium registry/images and do not change its existing
public-access setting, the gateway SKU or the model-serving path.

Adding the registry DNS zone changes registry resolution for **all clients in
the linked VNet**. Verify existing private clients can reach the registry private
endpoint; do not treat that DNS change as isolated to the new agent.

In create mode, the sample NSG is **not an outbound deny-all firewall**:
Azure default rules remain. Existing mode does not modify central network rules.
Private gateway inference is distinct from completely private control-plane,
identity and telemetry traffic. No NAT gateway, firewall or Azure Monitor Private
Link Scope is created. Validate platform outbound behavior and any existing
egress requirements before deployment; do not silently add paid egress resources
or claim that all traffic is private.

The new account is Entra-only with public access disabled. Its Terraform
`prevent_destroy` guard blocks accidental removal/replacement, including turning
off the flag after deployment. Network-injection changes require a deliberately
reviewed migration, not an in-place toggle. Do not copy upstream purge hooks or
enable public hosting to work around a failed private deployment.

The project capability host follows sample11's `capabilityHostKind = "Agents"`
body. That field is absent from both AzAPI 2.13's embedded schema and the
2025-04-01-preview generated project-host reference. Schema validation is
disabled **only for that resource**, matching the official sample. Other new
resources retain schema checks. Successful service-side provisioning remains a
deployment gate; offline checks do not establish support for the omitted field.

## Prepare an additive plan

Use the **existing authoritative Terraform state/backend and workload inputs**.
Do not initialize a second state against the same resources or use an unrelated
repository-local state. For source-only preparation use a clean snapshot without deployment state.
Any plan against a deployed workload uses its approved backend and identity;
do not make a second active state copy.

Complete the main guide's [input selection](../01-04-deployment.md#compose-the-inputs).
In the existing approved base input file, enable the new extension and save:

```hcl
enable_private_networking   = true
enable_private_hosted_agent = true
```

In **create** mode, `location` must equal `gateway_location` because the sample
uses one VNet. In **existing** mode, the agent subnet's VNet must be in `location`
and the gateway integration VNet in `gateway_location`; these may differ.
Supply the extra agent/registry IDs listed above. The agent integration subnet
must be at least `/27`, dedicated, delegated and RFC1918-only for this sample;
endpoint subnets must not use that delegated subnet.

Keep all input files, the selected ownership file and the final private
profile. For an already-private gateway:

```powershell
foreach ($name in @('workloadVarFile', 'networkOwnershipFile', 'additionalInputArgs',
                    'endpointCompatibilityArgs')) {
    if (-not (Get-Variable -Name $name -ErrorAction SilentlyContinue)) {
        throw "Missing $name. Restore the main guide's complete input selection."
    }
}
terraform plan -input=false "-var-file=$workloadVarFile" @additionalInputArgs `
    "-var-file=$networkOwnershipFile" '-var-file=01-04-profiles\private-only.tfvars.json' `
    @endpointCompatibilityArgs '-out=private-agent.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Private-agent plan failed.' }
terraform show private-agent.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the private-agent plan.' }
```

Do not apply until the plan shows only the reviewed additions. In particular,
reject replacement/deletion of the gateway, models, original account/project,
VNet or existing endpoints, and any planned public-access reopening.
In existing mode reject central subnet/NSG/zone/link changes too.

Only after reviewing permissions, cost and those additions:

```powershell
terraform apply private-agent.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Private-agent infrastructure apply failed; stop.' }
```

**Expected:** infrastructure is created, not a running agent application.
The application owner must complete the gates below; do not mark the agent
working merely because Terraform finishes.

`project_id` and `project_endpoint` still refer to the **old** project for
compatibility. Use the new `private_hosted_agent` output for account/project,
subnet, registry and gateway metadata. It contains no key values.

## Deployment and acceptance gates

1. Verify `Microsoft.App`, `Microsoft.CognitiveServices` and `Microsoft.Network`
   registration, hosted-agent region/capacity, effective policies, tags and roles.
   The agent subnet must be unused, dedicated and in non-overlapping RFC1918
   address space. Creating the S0 account is not a capacity guarantee.
2. Choose a deployment executor inside the VNet, such as the existing test VM.
   This extension does **not** grant that VM deployment or ACR build permissions.
   Review the exact azd workflow and assign only its required resource-scoped
   permissions before deployment. Keep temporary compute bounded and deallocate it.
   For an existing digest, use azd's explicit pre-built `image` configuration
   in a separate service directory without a Dockerfile. A package argument
   alone does not guarantee build suppression. Local builds need AcrPush;
   remote builds need Container Registry Tasks Contributor (and different
   permissions for ABAC registries). See the
   [existing/private ACR guide](https://learn.microsoft.com/azure/foundry/agents/how-to/deploy-hosted-agent-private-azure-container-registry).
3. Verify account/PE/capability-host provisioning and private DNS for Foundry,
   registry login/data endpoints and gateway. Verify runtime identity, ARM
   key retrieval, image pulls and telemetry connectivity. Outbound NSG allows
   alone do not prove an SNAT or firewall path exists.
4. Deploy the existing hosted application into the **new** project. No agent,
   image build, runtime session or model fallback is created by this Terraform.
   Discover the actual runtime managed-identity object ID; never use the old
   agent identity or a made-up placeholder.
   Verify the **runtime** AcrPull assignment separately; do not assume azd
   creates it. In the observed deployment, an authorized coordinator assigned
   this role on the exact registry without granting the VM role-write access.
   Preserve the project AcrPull assignment managed by Terraform.
5. Set `private_hosted_agent_runtime_principal_id` to that verified object ID
   and review the separate plan. It grants only gateway key retrieval at the
   existing gateway scope. With the test VM enabled, it reuses that narrow role
   definition; otherwise the extension creates an equivalent definition.
   Retrieve keys only in runtime memory, never Terraform, files or outputs.
6. Prove a fresh agent response with a matching gateway success trace, private
   DNS/route evidence, continued authenticated public network rejection and
   fresh telemetry. The deployment acceptance runner covers gateway/model
   and optional Blob probes, **not this hosted-agent acceptance**.

   After binding the runtime identity, retain that input in subsequent plans.
   Applying older configuration or omitting the enabled extension/runtime inputs
   does not represent the deployed end state.

Existing unrelated agents require no work for this reference path; their
cleanup is outside this guide. If provisioning fails after subnet attachment, investigate
the retained service-association link before retrying; do not repeatedly recreate
the same account on a potentially occupied subnet.

## Repeatable operation after deployment

### Retain the complete deployment inputs

Continue using the authoritative backend and the **current configuration
revision**. Do not apply a pre-extension checkout against the updated state,
copy state into another active environment, or drop the private extension flag.
Retain stable naming, monitoring and workload inputs as well as the selected
private profile.

Store the verified runtime object ID in a protected local input file, for
example `C:\secure\private-agent-runtime.tfvars.json`:

```json
{
  "enable_private_hosted_agent": true,
  "private_hosted_agent_runtime_principal_id": "<actual-runtime-object-id>"
}
```

Replace the placeholder only after discovering the deployed runtime identity.
The ID is the runtime's **principal/object ID**, not a client/application ID;
use its actual resource's **Identity** page or the application deployment output.
Have the application owner verify which identity executes the selected version.

Add the saved file to the main guide's additional-input list and rebuild its
arguments; this ensures later monitoring and acceptance plans retain the binding:

```powershell
$runtimeVarFile = (Resolve-Path -LiteralPath 'C:\secure\private-agent-runtime.tfvars.json').Path
$additionalVarFiles = @(@($additionalVarFiles) + @($runtimeVarFile) | Select-Object -Unique)
$additionalInputArgs = @($additionalVarFiles | ForEach-Object { "-var-file=$_" })
```

Review/apply a fresh `private-agent.tfplan` with the preceding plan/apply blocks
for the new runtime binding. The expected added role is the narrow gateway
key-reader binding, not broad access or replacements. Then, for subsequent drift:

```powershell
terraform plan -input=false "-var-file=$workloadVarFile" @additionalInputArgs `
    "-var-file=$networkOwnershipFile" '-var-file=01-04-profiles\private-only.tfvars.json' `
    @endpointCompatibilityArgs -detailed-exitcode
if ($LASTEXITCODE -eq 1) { throw 'Terraform plan failed; drift is unknown.' }
if ($LASTEXITCODE -eq 2) { throw 'Changes require review; do not auto-apply.' }
```

Exit 0 is a no-change plan, not a runtime test. Include any additional inputs
that were used for the deployment. The ingress profile remains last.
Never persist a gateway key in tfvars, agent metadata, command output or state.

### Separate the identities and their lifecycle

| Identity | Persistent access | Deployment-only access and ownership |
| --- | --- | --- |
| Foundry project | Terraform-managed registry AcrPull and configured project connections | Does not substitute for runtime access. |
| Hosted-agent runtime | Gateway key-reader via the optional Terraform binding; AcrPull on the exact registry | Discover the principal after deployment. The observed runtime AcrPull was assigned by an authorized coordinator, outside Terraform; retain its assignment ID and owner. |
| Private executor | Only its pre-existing baseline roles after the job | The observed job temporarily added Foundry User on the project and Reader on the account and registry. Remove only assignments created by that job. Different build/deployment workflows may need different scoped permissions. |
| Gateway | Model invocation and linked-DCR publishing permissions | Unchanged by agent deployment; not inherited by the agent or executor. |

Authenticate the executor with its own managed identity rather than copying
developer tokens to it. In the application workspace, select a separate azd
environment and point it at the `private_hosted_agent` outputs. Follow the
[hosted-agent deployment guide](https://learn.microsoft.com/azure/foundry/agents/how-to/deploy-hosted-agent-private-azure-container-registry)
for the installed extension. Terraform owns infrastructure: do not run a second
provisioning workflow against it.

For a prebuilt image, retain its digest and use explicit image passthrough with
remote build disabled; the observed workspace had no Dockerfile. Record the
agent name/version and actual principal after each deployment. Do not assume a
new version retains the same identity. If it changes, review both runtime roles
and the corresponding input update before removing any still-used assignment.

### Repeat the evidence, not the original provisioning

Obtain approval for billable invocation and temporary compute before rerunning.
Record the chosen environment, version, timestamp and evidence directory.

1. From a private client, verify Foundry, gateway and ACR login **and regional
   data** DNS against their expected private endpoint IPs. Confirm approved
   private connections and successful account/capability-host provisioning.
2. Invoke the selected version in a fresh session with `Reply with exactly OK
   and no other text.` Retain the response and trace identifier; an active
   agent status alone is insufficient.
3. Query the gateway workspace for that exact trace and invocation window.
   Require both the gateway request and the intended model-backend call to
   succeed; correlate route/alias and backend host/path, not merely any HTTP 200.
4. From outside the private route, use a currently valid gateway credential
   held only in memory. Require an explicit public-network-denial response.
   Authentication-specific 403, 401, DNS failure or timeout is not equivalent.
5. Check gateway/model/Foundry public-access settings, and independently test
   the preview agent invocation ingress boundary if required. Repeat every
   required alias and telemetry check for the new environment.
6. Remove only job-created temporary roles, preserve baseline roles, deallocate
   the executor and independently confirm both cleanup results. Run the
   no-change plan with the complete inputs above.

Example query, using the deployed gateway's `OTelSpans` table:

```kusto
let invocationStart = datetime(2000-01-01T00:00:00Z); // Replace with actual start.
let invocationEnd = datetime(2000-01-01T00:05:00Z);   // Replace with actual end.
OTelSpans
| where TimeGenerated between (invocationStart .. invocationEnd)
| where TraceId == "<actual-trace-id>"
| extend HttpStatus = coalesce(toint(Attributes["http.response.status_code"]), toint(Attributes["http.status_code"]), toint(ResultCode))
| extend Route = tostring(Attributes["http.route"])
| project TimeGenerated, TraceId, Kind, Name, HttpStatus, Route, ResultCode, Attributes
| order by TimeGenerated asc
```

`HttpStatus` and `Route` are explicitly derived above, not physical columns of
[OTelSpans](https://learn.microsoft.com/azure/azure-monitor/reference/tables/otelspans).
Inspect the backend host/path in `Attributes` locally; parse it as JSON if the
query client returns a string. Missing status/route information needs
investigation, not an assumed pass. Do not export the full attributes or rely
on an unavailable `ParentId` column.
These are **separate hosted-agent gates**: the existing
[deployment acceptance runner](end-to-end.md) does not perform them.
Retain operational evidence outside the published repository.

## Cost boundary

Plan for two additional Private Endpoints, private DNS queries,
hosted sessions, image build/pull, model tokens, telemetry and temporary executor
compute. Create mode also adds one ACR private DNS zone; existing mode reuses
the central zone, whose existing/query charges do not disappear. There is no
additional workload Cosmos DB, AI Search, registry or model
deployment. Existing resource costs remain. Obtain current regional pricing
before approval; policy-deployed helpers and any required egress solution are
additional, not included merely because the Terraform plan succeeds.

## Optional evaluation boundary

The hosted agent's `gpt-mini` gateway alias is not a model deployment in the new
Foundry project. Automatic Foundry test-data generation against that name
returned HTTP 400, `The specified deployment could not be found`, even though
the hosted agent itself worked. Do not add a separate model or bypass the
gateway just to make evaluation setup succeed. Local synthetic test cases can
be prepared without new Azure resources; preparing them is not an evaluation
run or a registered Foundry evaluation suite.

Fifteen local synthetic cases were prepared from the brief, friendly-assistant
instructions: exact output, greetings, arithmetic, translation, extraction,
sorting, classification, JSON formatting, brevity and missing-information
handling. They remain **prepared, not executed, uploaded or registered**.
The single live `OK` proof above is not a pass for this dataset.

For a later approved run, keep cases and result records in the agent workspace's
`.foundry\datasets`, `.foundry\suites` and `.foundry\results` directories. Use a
fresh session per independent case, record the selected version, response and
trace, and compare exact/JSON assertions or the documented manual criteria.
Report manual cases as pending until reviewed; never infer evaluation scores
from deployment success. No extra Azure model is needed to prepare local cases.
