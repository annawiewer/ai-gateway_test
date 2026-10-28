# AI Gateway and Foundry with Terraform

Manage an Azure AI Gateway that routes calls to Foundry models. This is standalone
Terraform for the [Foundry AI Gateway Python sample](https://github.com/Azure-Samples/simple-foundry-hosted-agent-python-aigateway), not an `azd` app.

## Start here: step-by-step deployment

> [!IMPORTANT]
> **[Open the step-by-step deployment guide (`deployment.md`)](deployment.md#start-here).**
>
> Follow that guide to deploy this sample: prerequisites, path selection, required
> inputs, files to edit, commands to run, expected results and stop conditions.
> **This README is the overview and architecture reference, not the deployment procedure.**

**Already have central network and DNS?** The same guide includes
[existing-network integration at a glance](deployment.md#existing-network-integration-at-a-glance):
the two environment-specific input files, the platform handoff and where to
continue.
An existing network does **not** mean the gateway has already been deployed.
The guide separates network ownership from workload/state ownership;
neither the `create` nor the `existing` choice changes the gateway SKU.

> [!NOTE]
> **Legacy SKU and migration deadline:** This sample uses
> `Microsoft.ApiManagement/service` with SKU `AIGateway`. Microsoft requires
> migration **before January 15, 2027**. This SKU is retained here for the
> private-endpoint scenario: as of October 25, 2026, the newer
> `Microsoft.ApiManagement/aigateways` resource does **not** support private
> endpoints. This is a time-limited preview reference, not a long-term deployment
> target. Plan migration without assuming private-endpoint feature parity;
> this sample does not perform that migration. See Microsoft's
> [migration deadline and limitations](https://learn.microsoft.com/azure/api-management/ai-gateway-resource).

> [!IMPORTANT]
> **Terraform Registry disclaimer (checked October 25, 2026):** No dedicated
> Microsoft-published Registry module was identified for the standalone
> `AIGateway` preview used here. General API Management and community gateway
> modules do exist; this directory is a repository-specific Terraform
> configuration, not an official Registry module. Instead, it uses Microsoft's
> **`Azure/azapi` provider** to manage explicit ARM resource types and preview
> API versions. See [how this is implemented](deployment.md#terraform-implementation)
> for the distinction and validation limits.

> **Preview PoC, not production.** The AI Gateway preview has **no SLA**. Everything
> here is billable (model calls, Premium ACR, Storage, monitoring). Read the
> [limitations](docs/reference.md#limitations) before applying.

This sample uses `Microsoft.ApiManagement/service` with SKU `AIGateway`.
Check resource-type availability for the target subscription and region before deployment.
See [resource type and lifecycle](docs/reference.md#resource-type-and-lifecycle)
for the exact ARM contract and Microsoft's migration guidance.

<a id="choose-your-network-foundation"></a>

## Choose a network foundation

For private connectivity, choose **one** ownership option:

| Starting point | Network mode | What this sample does |
| --- | --- | --- |
| **No gateway network or private DNS yet** | [`create`](profiles/network-create.tfvars.json) (default) | Creates the sample's gateway VNet, subnets, NSGs, private DNS zones and links. This is a gateway foundation, **not** a corporate hub, firewall or landing zone. |
| **Centrally managed network and DNS already exist** | [`existing`](profiles/network-existing.tfvars.json) | Reads approved subnet/zone IDs and creates new workload private endpoints. The platform retains ownership of networks, routing, firewall, resolver, DNS zones and links. |

These are **ownership choices, not public/private access profiles**. Public
remains the default; `existing` requires `enable_private_networking = true`.
Combine a network profile with the appropriate private-access profile below.
The [deployment guide](deployment.md#network-foundation-create-or-existing)
shows both combinations, required inputs and a local Terragrunt adapter.
Replace every fictional ID in the existing-network example before use; missing
inputs fail rather than silently creating a parallel network.

**Finding resource IDs:** follow
[Find resource IDs and fill in the network input file](deployment.md#find-resource-ids-and-fill-in-the-network-input-file)
for Azure Portal steps, the field-by-field mapping and the Terragrunt alternative.
Keep the values in the organization's approved configuration. Do not share
credentials, Terraform state or environment-specific inputs through unapproved channels.

Network and DNS are separate concepts, but this implementation pairs them:
create both foundations, or reuse both. It does not offer a create-network /
external-DNS hybrid. New private endpoints belong to the workload in either mode;
their DNS zone groups can belong to the workload or, in existing mode, the
platform. Central DNS automation must finish before connectivity is accepted.

**Already deployed with sample-managed networking?** Do not toggle to `existing`
as an ordinary update: it would remove sample-managed resources. The created
VNet has a `prevent_destroy` guard; do not bypass it. Retain the
current mode, resource names/addresses and authoritative state until a separate
state/migration plan is reviewed. Do not copy state or import the same resources
into a second owner. Switching workload/platform DNS zone-group ownership also
requires a separately reviewed state handoff, not a routine flag flip.
The selected network mode does not change the `AIGateway` SKU.
Recorded live evidence includes the isolated existing-network rehearsal below;
repeat acceptance for the target network and central DNS topology.

### Existing-network reference architecture

This reference combines **`existing` network ownership** with the gateway/model
**`private-only` target after approved staged setup**. Subnet roles do not
prescribe a VNet count or hub/spoke topology.

```text
Private client -> gateway private endpoint -> AI Gateway
AI Gateway -> outbound VNet integration -> model private endpoint -> Foundry model
```

The existing resolver and central private DNS zones provide name resolution;
they do not carry model traffic. Supporting agent, storage and monitoring
resources are outside the synchronous request path. Terraform prepares agent
infrastructure, not a running agent application.

Continue with [network and DNS](deployment.md#existing-network-connectivity-reference),
[resource ownership](deployment.md#platform-handoff-before-a-plan) or the
[end-to-end request sequence](docs/architecture.md#end-to-end-private-request-flow).

<a id="choose-your-networking-path"></a>

## Choose a networking path

Choose between **Public** and **Private-only**. Public is the Terraform default;
Private-only disables public access to both the gateway and model account.

| Path | Private endpoints | Gateway public access | Model public access |
| --- | --- | --- | --- |
| [Public](#public-endpoint-path) | None | Enabled | Enabled |
| [Private-only](#private-only-path) | Gateway and model account | **Disabled** | **Disabled** |

The private setup guide uses temporary provisioning stages to establish and
verify connectivity before disabling public access. These are **not a third
deployment path** and do not satisfy Private-only acceptance.

**Update, October 25, 2026:** disabling public ingress through the portal succeeded
for the observed gateway after a long wait; ARM confirmed `Disabled` / `Succeeded`
and an `Approved` / `Succeeded` private connection. The previous configuration
blocker was resolved **for that gateway**, not a confirmed universal product fix.
A subsequent private hosted-agent invocation
returned **OK**, with gateway and model-backend **HTTP 200** in the same trace;
an authenticated public gateway request returned an explicit network-denial
**HTTP 403**. The final Terraform plan had no changes.
See [evidence and verification boundaries](docs/reference.md#private-only-gateway-ingress-status).

**Update, October 27, 2026:** a separate isolated Sweden Central rehearsal created
the original `AIGateway` through Terraform using independently owned network/DNS,
then disabled gateway and model public access through staged Terraform updates.
Both private model aliases, authentication/network boundaries, telemetry,
central firewall routing and four independent no-change plans passed.
This does not prove private-from-first-create or verify another target environment.
Hosted-agent execution was not tested in that rehearsal.

**Already using the private profile?** Follow [existing private deployments](docs/private-connectivity.md#existing-private-deployments).
Keep the **selected** profile on every plan, including drift and monitoring
changes, together with all workload inputs and the selected network-ownership
file. Put the private-access profile after those files; retain any explicitly
approved endpoint-compatibility exception from the
[input selection](deployment.md#compose-the-inputs). Do not repeat
temporary-public staging for an already-private gateway or backend.

## Access

Grant identity-based access with **Microsoft Entra ID**, or manage **API keys**.
This choice is independent of the two networking paths.

| Access option | Configuration |
| --- | --- |
| Microsoft Entra ID | Add callers to `gateway_access_principals`; Terraform grants **AI Gateway Models User** for all models in this gateway. Test with `.\scripts\Test-ModelAliases.ps1 -Authentication EntraId`. |
| API keys (existing default) | Leave the map empty and use `.\scripts\Test-ModelAliases.ps1`. Existing keys remain available when Entra callers are added. |

This is **additive**, not an Entra-only switch. The existing hosted agent and
private test VM keep their API-key flow; the gateway keeps its managed identity
for backend model access. See [Access configuration](docs/reference.md#access)
for identity types, token requirements and post-deployment changes.

**Live-verified over the private route:** both sample models returned **200** with
managed-identity Entra access, **403** without the invocation role, and **401**
for missing/invalid credentials. API-key calls also passed; gateway/backend
traces matched. The temporary grant was removed afterward. This verifies the
managed-identity caller flow, not custom delegated-user applications.

<a id="before-you-start"></a>

## Prerequisites and decisions

**Check these first:**

- [ ] Terraform 1.11+ (below 2.0) and Azure CLI installed
- [ ] Subscription/region access to the resource types used here, and to Foundry hosted agents if needed
- [ ] Scoped permission to create workload resources and their required role assignments
- [ ] In existing-network mode: approved subnet/DNS inputs and scoped read/join, private-endpoint and DNS permissions; see [platform prerequisites](docs/private-connectivity.md#existing-network-prerequisites)
- [ ] If enabling the test VM: permission to manage its **custom role definition**, not just role assignments; see [test-client permissions](docs/private-connectivity.md#test-client-permissions)
- [ ] Providers registered: `Microsoft.ApiManagement`, `Microsoft.Web`, `Microsoft.CognitiveServices`, `Microsoft.Storage`, `Microsoft.ContainerRegistry`, `Microsoft.OperationalInsights`, `Microsoft.Insights`, `Microsoft.Monitor` (this sample does not register them for you)
- [ ] Quota for the model and SKU in the target region

**Deployment decisions:**

- **Public endpoints OK?** If the applicable policy prohibits public gateway or model endpoints, even temporarily, do not run this sample unchanged.
- **Need private hosted-agent execution?** Enable the [private hosted-agent configuration](docs/private-hosted-agent.md) from the start for the new agent account. Terraform creates network injection, private endpoints and project dependencies; deploy the application and bind its actual runtime identity afterward. This reference path has passed a live test; it is not enabled by default.
- **Need private-only gateway ingress?** Select the explicit private-only end-state profile after endpoint approval and private-route verification. Original-SKU creation and staged Terraform closure passed in one isolated rehearsal; private-from-first-create and other environments still need separate proof. See the [status](docs/reference.md#private-only-gateway-ingress-status).

### Platform team: policy compatibility

Before deployment, review the effective Azure Policy assignments at the target
scope, including inherited management-group and subscription assignments,
initiative parameters, exclusions and applicable exemptions. Compare them with
the resources and settings in the selected deployment path.

| Check | Required outcome before apply |
| --- | --- |
| Allowed regions, resource types, SKUs and mandatory tags | All planned resources comply, including Azure-managed monitoring helper resources. |
| Public network access for the gateway, model account, Storage and Container Registry | The selected path meets the approved requirements, including any temporary access used during staged deployment. |
| Private endpoints, DNS, routing and outbound restrictions | Deployment clients and each runtime identity have a supported network path to the services they need; disabling public access alone does not provide that path. |
| Identity, authentication and RBAC requirements | Deployment permissions, managed identities, optional Entra caller roles and retained gateway API keys are compatible with the applicable controls. |
| Monitoring and security requirements | Required diagnostics, retention and destinations are accounted for, along with any automatically enabled Defender plans and their costs. |

Resolve incompatibilities in the IaC and deployment inputs **before apply**.
For example, if the applicable policies require private Storage access, provide or reuse
the necessary private endpoint, DNS and connectivity for every client that
needs Storage. This is a conditional requirement, not a prerequisite for every
deployment. Do not disable policies or reopen restricted endpoints to make the
sample deploy.

A successful `terraform plan` is **not** proof of policy compatibility:
`Deny` can block resource creation, `Modify` can change requested settings, and
`DeployIfNotExists` can deploy related resources. After deployment and any policy
remediation, inspect the actual configuration, run a fresh plan with the same
inputs, and verify DNS, connectivity, authentication and telemetry from the
intended clients. Investigate policy-induced drift rather than blindly applying
a plan that would undo an enforced setting.

## What gets deployed

Start with a single request: **an application sends a prompt to the gateway; the
gateway checks access and policy; the selected Foundry model generates the
answer.** The supporting resources below prepare a later agent application
and make requests observable.

| Component | Purpose in this sample |
| --- | --- |
| **AI Gateway** | One model API endpoint for clients. It checks the runtime API key or Entra token and invocation role, applies a token limit per caller, resolves the model alias and forwards the request. It does not run the model or agent code. |
| **Foundry model account** | Runs the actual model deployments. It trusts the gateway's managed identity, not the client's gateway API key. |
| **Foundry hosted-agent account and project** | Provide the environment, connections and project permissions for a *later* agent application. **No agent, image or running container is deployed by Terraform.** |
| **Container Registry and Blob Storage** | Store a later agent's container image and provide connected data storage. They are not extra model-serving hops and are not prerequisites for a simple client to call the gateway. |
| **Monitoring** | Application Insights links the destinations; Log Analytics stores logs and traces; a separate Azure Monitor workspace stores metrics. Azure-managed collection endpoints and rules ingest and route gateway telemetry. |
| **Private network (private path)** | Creates or reuses the selected network/DNS foundation. New gateway and model private endpoints plus outbound gateway integration provide the private route; DNS and approved routing make it usable. |
| **Optional private test VM** | Tests DNS, routing and inference from an approved private client subnet. It is opt-in and not the agent runtime; an existing suitable private client can replace it. |

See the [service-by-service architecture guide](docs/architecture.md) for
**base private connectivity**, the **private-agent reference** and separate
**API-key versus optional Entra authentication flows**. Applications authenticate
with **Entra ID or an API key**; the gateway uses its separate managed identity
for the backend. The caller's hosting location is an application deployment
decision; Private-only also requires private DNS and network connectivity.
The optional hosted agent is not a required hop for direct application model
calls. Telemetry is separate from the synchronous response, and a configured
connection is not proof of runtime traffic.

Both paths manage all three core components. Hosted-agent infrastructure is
included even if you only test model calls.

### Private agent reference for new deployments

Use `enable_private_networking = true`, `enable_private_hosted_agent = true`
and the selected private-only ingress profile. These inputs create the agent
account with its required network configuration **at creation time**; they do
not deploy the application. The subsequent application deployment and scoped
runtime-role binding complete the reference setup. The public defaults remain
unchanged. The agent extension does not change the gateway resource type or SKU.

The [private-agent operating guide](docs/private-hosted-agent.md) covers
deployment stages, permanent versus temporary roles, repeat checks and the
local synthetic cases (prepared, not executed). Its Basic setup uses
platform-managed agent data; it does not require the base sample's Blob
connection for the demonstrated model call.

### Shared resource and authentication boundaries

All sample-created application resources use **one shared resource group**:
`rg-<environment_name>-<resource_token>-gateway`. The existing gateway group name
and Terraform address are retained; the AIGateway SKU and agent monitoring are
unchanged. Gateway OTLP enablement can create **Azure-managed
monitoring helper groups**, with one gateway publishing role on the linked DCR.
This explicit exception, its costs and the required two-stage setup are covered
in [gateway monitoring](docs/monitoring.md).
Reused network/DNS resources remain in their platform-owned groups and state.

**Upgrading from the former three-group layout is a migration, not a harmless
refactor.** Terraform can propose backend replacements and deletion of the old
groups. Do not apply until the exact migration/recreation and any data loss have
been approved. See [single-group consolidation](docs/reference.md#single-group-consolidation).

**Authentication in both paths** (independent of public or private routing):

```text
Client --(API key OR Entra token + invocation role)--> AI Gateway --(managed identity)--> Foundry model account
```

A **model alias** (for example, `gpt-mini`) is the name clients send. It does not have to match the underlying model name (for example, `gpt-4.1-mini`).

## Shared setup

Use the [deployment guide's numbered sequence](deployment.md#runbook-order).
It includes [tool and checkout checks](deployment.md#prerequisites),
[input values and their sources](deployment.md#inputs-and-state),
[network-ID lookup](deployment.md#find-resource-ids-and-fill-in-the-network-input-file),
[platform handoffs](deployment.md#platform-handoff-before-a-plan),
[plan review](deployment.md#review-every-plan-before-apply) and monitoring.

For a **new workload**, copy the example only when no approved input file
exists and the workload backend is agreed. For an **existing workload**, retain
its input files and authoritative state; do not overwrite them with examples.
The existing platform network keeps its own state in both cases.
Optional agent deployment, Terragrunt and repair procedures are separate branches,
not extra steps everyone must execute.

<a id="private-connectivity-path"></a>

## Private-only path

Use [profiles/private-only.tfvars.json](profiles/private-only.tfvars.json)
for the final configuration: gateway and model public access are both disabled.
Use it with the selected network-ownership profile and complete workload inputs,
not instead of them.

```text
Private client -> gateway private endpoint -> gateway outbound VNet integration -> model private endpoint
```

Follow the [private-connectivity guide](docs/private-connectivity.md) for the
staged plan/apply, private probe, and VM lifecycle. Its
`private-connectivity` file is an intermediate provisioning profile, not an
alternative end state. Complete the gateway-disable stage and verify both
private inference and authenticated public-network rejection before acceptance.

**Do not use the public path for this private configuration.** Omitting the
selected profile can plan removal of private networking or re-enable public
access, depending on the other inputs. The intermediate `private-connectivity`
profile sets gateway ingress to `Enabled`; never reuse it for an already-disabled gateway.

## Public endpoint path

Use this path only for a deployment intentionally configured without private
networking. It is not a prerequisite for the private path.

Follow [Public in the step-by-step guide](deployment.md#public) for complete
input arguments, saved-plan review, the separately approved apply and the
per-alias probe. A reply such as `gpt-mini: Hello!` is a public-path smoke check,
not private-route proof or full acceptance. The final full plan must have no
pending changes. Keep [probe compatibility](docs/reference.md#probe-compatibility)
and the separate acceptance requirements in view.

## Additional runtime checks

For a reproducible private-path rehearsal, use the
[end-to-end runbook](docs/end-to-end.md): credential-free CI, a guarded backend
verifier and a separate authenticated portal review including fresh metrics.
The portal evidence validator checks completeness; it does not automate the UI.

Complete the [deployment acceptance guide](docs/acceptance.md) for either path.
It includes commands, expected results, and failure boundaries for missing and
invalid keys, the six service RBAC assignments plus the DCR publishing role, Foundry connections, telemetry,
and the final drift check. A successful model call alone is not full acceptance.

## Going further

- [Version and verification scope](docs/reference.md#version-and-verification-scope)
- [Reference](docs/reference.md): file guide, all inputs, outputs, networking, state and security, offline tests, limitations
- [Cost and cleanup](docs/reference.md#cost-and-cleanup)
