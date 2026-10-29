# Reference

This is a technical lookup, not the execution order. For file-role basics, read
[Understand the sample](understand-the-sample.md). Operators start with the
[shared deployment procedure](../deployment.md#start-here); use its
[input catalogue](../deployment.md#inputs-and-state) to find values and its
[failure/resume guide](../deployment.md#if-something-fails-or-you-open-a-new-terminal)
when a step stops. Historical migrations below are not routine setup steps.

Details for both [networking paths](../README.md#choose-your-networking-path).
Review the limitations before changing an existing deployment.

<a id="customer-handoff"></a>

## Version and verification scope

**Reviewed implementation baseline:**
[`dfa84ba9004afc2f03f723432fc0b05e6bc531c8`](https://github.com/annawiewer/ai-gateway_test/commit/dfa84ba9004afc2f03f723432fc0b05e6bc531c8).
This identifies the reviewed Terraform configuration and runtime scripts, not a
version that you must switch to or a production certification.

Use the **exact source revision approved for your deployment**, including its
documentation, as described in the [checkout steps](../deployment.md#2-open-the-approved-source-revision).
The `main` branch can change; record the commit or tag you actually use so the
deployment is reproducible. Keep an existing deployment's approved revision
unless its owner has approved an update.

**Change summary**

- Added paired `create`/`existing` network ownership, validated existing subnet
  and central DNS-zone inputs, and a Terragrunt adapter for independently owned
  platform units. New private endpoints stay workload-owned; DNS zone groups
  have one explicitly selected owner.
- Corrected optional private-agent acceptance to check the separate private
  account, and clarified staged/final evidence, telemetry and public-network
  rejection. The original `AIGateway` SKU is unchanged.
- The [step-by-step guide](../deployment.md#start-here) includes an
  [existing-network entry](../deployment.md#existing-network-integration-at-a-glance),
  an [ownership/approval table](../deployment.md#platform-handoff-before-a-plan),
  state-preservation guidance, manual portal evidence and recovery without
  reopening an already-private gateway. These documentation updates do not change
  the Terraform resource definitions or SKU.

| Evidence or boundary | What has been verified and what remains |
| --- | --- |
| Offline checks | The implementation has Terraform/script regression checks. The corrected acceptance fixtures and documentation examples were checked offline; this does not verify your network or Azure Policy. |
| Scoped live evidence | The [October 27 rehearsal](#private-only-gateway-ingress-status) created the original SKU with separately owned network/DNS, completed staged private closure, and checked private calls, network/authentication boundaries, telemetry, routing and no-change plans. This is historical evidence for that environment, not a new deployment of every subsequent documentation revision. |
| Not established by that rehearsal | Private-from-first-create, another subscription/region, your backend/CI/PIM/policies, or optional hosted-agent, Blob and registry runtime acceptance. The earlier agent proof has its own separate scope. |
| Required for your deployment | Record the source revision you use and the input/state owners, then complete the [deployment acceptance checklist](../deployment.md#deployment-acceptance-checklist). Keep keys, state and environment-specific evidence out of the public repository. |

## File guide

| File | What it controls |
| --- | --- |
| [terraform.tfvars.example](../terraform.tfvars.example) | Template for your ignored `terraform.tfvars` |
| [profiles/private-connectivity.tfvars.json](../profiles/private-connectivity.tfvars.json) | Four private-connectivity settings, including explicit gateway endpoint approval (no secrets) |
| [profiles/private-only.tfvars.json](../profiles/private-only.tfvars.json) | Explicit private-only gateway end state after staged private connectivity (no secrets) |
| [profiles/network-create.tfvars.json](../profiles/network-create.tfvars.json) | Sample-managed network/DNS ownership; independent of public/private access |
| [profiles/network-existing.tfvars.json](../profiles/network-existing.tfvars.json) | Minimal existing-network/DNS ownership example; replace every fictional ID in an untracked copy |
| [examples/terragrunt-existing.hcl.example](../examples/terragrunt-existing.hcl.example) | Local-root adapter for your network and DNS dependency outputs; adapt existing include/backend paths |
| [variables.tf](../variables.tf) / [outputs.tf](../outputs.tf) | Inputs, validation, outputs |
| [ai-gateway.tf](../ai-gateway.tf) | Gateway, provider, catalog, aliases, runtime key, telemetry exporter |
| [foundry-models.tf](../foundry-models.tf) | Model account and versioned deployments |
| [foundry-agents.tf](../foundry-agents.tf) | Agent account/project, Storage, Premium ACR, connections |
| [main.tf](../main.tf) / [rbac.tf](../rbac.tf) | Naming, shared resource group, monitoring, role assignments |
| [private-network-context.tf](../private-network-context.tf) | Ownership selection, existing-resource lookups and resolved network metadata |
| [private-network.tf](../private-network.tf) | Conditional sample-owned VNet, subnets, NSGs, private DNS zones and VNet links |
| [private-endpoints.tf](../private-endpoints.tf) | Workload private endpoints, gateway approval and endpoint DNS associations; still active when reusing the foundation |
| [private-test-client.tf](../private-test-client.tf) | Optional probe VM and NIC |
| [private-hosted-agent.tf](../private-hosted-agent.tf) / [private-hosted-agent.md](private-hosted-agent.md) | Opt-in additional private Foundry account/project; separate application deployment |
| [scripts/Test-PrivateGateway.ps1](../scripts/Test-PrivateGateway.ps1) / [private-path-probe.py](../scripts/private-path-probe.py) | Private probe (wrapper sends the Python to the VM) |
| [scripts/Test-ModelAliases.ps1](../scripts/Test-ModelAliases.ps1) | Test every alias from a connected client using an API key or Entra token |
| [scripts/Get-GatewayMonitoring.ps1](../scripts/Get-GatewayMonitoring.ps1) / [monitoring.md](monitoring.md) | Read-only bounded OTLP readiness, linked managed groups, two-stage setup |
| [tests](../tests) | Offline Terraform and Python tests |
| [acceptance.md](acceptance.md) | Deployment runtime checks, expected results and evidence boundaries |
| [versions.tf](../versions.tf) / [.terraform.lock.hcl](../.terraform.lock.hcl) | Provider versions and checksums (commit the lock file) |

All root `.tf` files are loaded together. Foundation and endpoint files separate
responsibilities, not modules, resource addresses or states.

## Inputs

Required values are in the operator guide's
[input catalogue](../deployment.md#3-fill-in-the-required-values);
tool/provider requirements are in its [prerequisites](../deployment.md#prerequisites).

| Input | Purpose and default |
| --- | --- |
| `environment_name` | Naming and tag label. Default `aigateway`. |
| `storage_public_network_access` | Default `Enabled`. Set `Disabled` if policy requires it; never override the policy by reopening access. |
| `enable_storage_private_endpoint` | Default `false`. With private networking and storage public access disabled, creates a Blob PE/DNS path for VNet clients. The optional VM receives storage-account-scoped Blob Data Reader for its read-only probe. Does not integrate hosted-agent networking. |
| `developer_principal_id` | Entra object ID for developer access. Empty means no developer roles. |
| `developer_principal_type` | `User`, `Group` or `ServicePrincipal`. Default `User`. |
| `gateway_access_principals` | Default `{}`. Map of caller `principal_id` and optional `principal_type` (default `ServicePrincipal`); grants AI Gateway Models User at gateway scope. Independent of developer/backend roles; keys remain available. |
| `publisher_name`, `project_display_name`, `project_description`, `tags` | Display metadata and tags |
| `enable_private_networking` | Default `false` (Public). Enables private endpoints and gateway outbound integration; use the explicit private-access profiles for the selected public-access posture. |
| `private_network_mode` | `create` (default) or `existing`. Ownership only; `existing` requires private networking. No automatic fallback or network/DNS hybrid. |
| `existing_private_network` | Default `null`, required only in `existing` and not allowed in `create`. Object containing `gateway_subnet_id`, per-service `endpoint_subnet_ids` in the workload `subscription_id`, logical `private_dns_zone_ids` (which may be in another subscription), and optional `agent_subnet_id` / `client_subnet_id` when the respective features are enabled. See the [complete field/zone contract](private-connectivity.md#existing-network-prerequisites). |
| `private_dns_zone_group_management` | `workload` (default) or `platform` (existing mode only). Selects who creates the new endpoints' DNS zone groups, not who creates the endpoints. Platform readiness is a separate gate; Terraform does not wait for policy. |
| `private_network_address_prefix` | Created-foundation VNet IPv4 /16 only. Default `10.247.0.0/16`. Pick a non-overlapping range before creation. Existing mode reads actual subnet IPv4 CIDRs instead. |
| `enable_private_test_client` | Default `false`. Requires private networking and, in existing mode, an explicit `client_subnet_id` in workload `subscription_id`. VM/NIC location follows that subnet's actual VNet. |
| `enable_private_hosted_agent` | Default `false`. Adds a separate VNet-injected Basic account/project and new Foundry/registry private endpoints; preserves the original account. Create mode adds an agent subnet and requires `location = gateway_location`; existing mode requires a delegated `agent_subnet_id` in the agent region, at least `/27` and wholly within this sample's supported RFC1918 IPv4 subset, plus `agents` / `registry` endpoint subnet IDs and the `registry` zone ID. |
| `private_hosted_agent_runtime_principal_id` | Default empty. Set only after discovering the new agent's real managed-identity object ID; creates a gateway-scoped key-reader binding. |
| `private_test_client_ssh_public_key` | OpenSSH **public** key, required when the VM is created |
| `private_test_client_vm_size` | Default `Standard_B2s_v2`. Check availability and quota. |

**Each `model_deployments` entry** requires `model_name`, `model_version`, `capacity`, and `token_limit`.

- `capacity` is a quota unit specific to the model SKU.
- `token_limit` is the gateway's tokens-per-minute limit per identity.
- They are independent. Do not convert one to the other.

Optional fields: `model_format`, `sku_name`, `api_format`, `endpoints`, `description`. Match the API format and endpoints to the model. See [variables.tf](../variables.tf) for types and validation.

## Access

Choose **Microsoft Entra ID** or **API keys** independently of Public/Private-only.
Authentication does not create the required network/DNS route. Optional identity
fields are not required merely to complete this reference.

### Find optional principal IDs

Use an **object/principal ID** in the gateway subscription's tenant, not an
application/client ID. Ask the identity owner for the approved object and scope;
resource visibility or a copied ID is not a permission grant.

| Optional identity | Portal location or source |
| --- | --- |
| User or group in `gateway_access_principals` | **Microsoft Entra ID > Users / Groups > selected object > Overview > Object ID**. |
| Application service principal | **Microsoft Entra ID > Enterprise applications > selected application > Properties > Object ID**, not the app registration's Application (client) ID. |
| System-assigned managed identity | The actual Azure resource's **Identity > System assigned > Object (principal) ID**. |
| User-assigned managed identity | **Managed Identities > approved identity > Overview > Principal ID**, not Client ID. |
| Private hosted-agent runtime identity | Discover from the **deployed agent runtime/version**, not the project identity; follow the [agent deployment gates](private-hosted-agent.md#deployment-and-acceptance-gates). Leave its optional input unset until that identity exists. |

Do not add Entra callers or agent runtime bindings when the feature has not been
selected. Runtime key-read and image-pull grants are distinct from caller invocation.

### Add caller roles without replacing existing inputs

To add Entra callers, extend the existing ignored input file:

```hcl
gateway_access_principals = {
  application = {
    principal_id   = "<actual-managed-identity-or-service-principal-object-id>"
    principal_type = "ServicePrincipal"
  }
  operators = {
    principal_id   = "<actual-group-object-id>"
    principal_type = "Group"
  }
}
```

Use object IDs in the gateway subscription's tenant, **not application/client IDs**.
Supported types are `User`, `Group` and `ServicePrincipal` (default, including
managed identities); each object ID may appear once. Terraform assigns **AI Gateway Models User**
(`a6b68e3d-a1f0-4c60-8678-237c050cf4ea`) at the **gateway resource scope**:
all models, not MCP tools, management operations or key retrieval. If you require
one-alias access, use a separately reviewed alias-scoped assignment instead.
Deployment credentials need role-assignment permission at this scope.

This can be added **after deployment** with the original state and complete
inputs. Keep the approved ownership/access inputs and any post-profile endpoint
exception on every plan, using [input composition](../deployment.md#compose-the-inputs).
Review the saved plan, then apply it. Keep map keys stable and retain entries on later plans;
removing an entry removes its Terraform-managed role assignment. If an equivalent
role already exists outside Terraform, import it at the intended address or keep
it externally managed rather than creating a duplicate.

### Token and consent contract

For a client calling as itself, request a token for audience
`https://azure-api.net/aigateway` (SDK scope
`https://azure-api.net/aigateway/.default`). Custom apps signing in users need
delegated `https://azure-api.net/aigateway/Data.All` consent **and** the user's
invocation role. That custom-app consent setup does not apply to managed
identities, client credentials or built-in Azure CLI/PowerShell clients.
Send `Authorization: Bearer <token>`, not the ARM or model-backend token.
See the [portal security and identity guide](https://ai.gateway.azure.com/docs/security-identity).

For custom delegated-user clients, that guide identifies the **Azure AI Gateway
Dataplane** application as `18550318-e177-4205-a743-6816d6fcdc3f`.
An Entra client uses the authorization header instead of `api-key`; gateway
keys remain available to other clients. For a workload calling as itself, use
its supported token flow and bind the invocation role to that workload.
Confirm preview availability, token acquisition, role propagation and client
compatibility before changing production authentication. Key revocation is a
separate reviewed migration, not part of this additive configuration.

### Verify the selected client

```powershell
# Run only after deployment, from a client with the selected route.
.\scripts\Test-ModelAliases.ps1 -Authentication EntraId
# Existing default:
.\scripts\Test-ModelAliases.ps1 -Authentication ApiKey
```

The Entra probe uses the current Azure CLI identity; it does not read keys or
fall back to them. It makes billable requests to every compatible alias and
requires network/DNS access to the selected gateway. Verify role propagation,
authorized and unauthorized callers, and telemetry before migrating clients.
Offline checks are not a live Entra proof.

**Live-verified:** a managed-identity caller reached both sample aliases over the
private endpoint: HTTP 403 before the Terraform-managed invocation grant, HTTP
200 afterward, with matching gateway/backend traces. Missing, invalid and
wrong-audience credentials returned 401; API-key calls remained successful.
The temporary grant was removed and the final plan had no changes. This does
not validate custom delegated-user clients or migrate the hosted agent.

**Additive, not Entra-only:** no API key is disabled or deleted. The existing
agent and private VM retain their key-reader roles and API-key calls. The gateway's
backend **Foundry User** binding (`53ca6127-db72-4b80-b1b0-d745d6d5456d`) remains
scoped to the model account; it is not a caller invocation grant. Neither adding
callers nor leaving the map empty certifies that other externally managed
invocation roles are absent.

## Outputs

| Output | Use it for |
| --- | --- |
| `gateway_endpoint` | Base URL for runtime calls |
| `gateway_api_key_id` | ARM ID for retrieving the key. **Not the key value.** |
| `model_deployment_ids` | Model IDs keyed by alias |
| `model_api_configuration` | API format and endpoints per alias; compatibility check for both sample probes |
| `project_endpoint`, `project_id` | Hosted-agent app setup (not a model-call URL) |
| `private_hosted_agent` | New private project, subnet, registry and gateway metadata when explicitly enabled. Original project outputs are unchanged. Not runtime proof. |
| `container_registry_endpoint`, `storage_account_name` | Image and artifact setup for the agent app |
| `resource_group_name` | The shared application group; excludes verified Azure-managed OTLP helper groups |
| `resource_groups` | Compatibility map: `gateway`, `models` and `agents` all contain that same group name |
| `gateway_id`, `foundry_models_id`, `application_insights_ids` | Resource and telemetry lookup |
| `gateway_monitoring` | Nonsecret actual OTLP endpoints/DCR, Insights and expected Log Analytics IDs; not proof of readiness/delivery |
| `private_network_configuration` | Selected network mode, effective subnet IDs/IPv4 prefixes, DNS zone IDs and zone-group owner; see [network metadata](#network-metadata) |
| `private_endpoint_ids`, `private_test_vm_id`, `private_probe_configuration` | Private-path lookup (VM outputs only when the test client is enabled) |

Outputs do **not** include runtime key values or telemetry connection strings.
Services use managed identities. Get the key through your approved secret process.
Never put keys in `.tfvars`, terminal output or source control.

### Network metadata

With private networking enabled, `private_network_configuration` describes the
selected foundation without requiring a test VM:

| Field | Meaning |
| --- | --- |
| `mode` | `create` or `existing` |
| `gateway_subnet_id` | Effective gateway integration subnet ID |
| `endpoint_subnet_ids` | Service-to-subnet-ID map for the enabled private endpoints |
| `endpoint_subnet_prefixes` | Service-to-IPv4-CIDR-list map from the selected subnet metadata; services need not share one range or VNet |
| `private_dns_zone_ids` | Logical zone-key-to-ID map |
| `dns_zone_group_management` | `workload` or `platform` |
| `agent_subnet_id`, `client_subnet_id` | Optional integration/probe subnet IDs for the corresponding enabled features |

`private_probe_configuration` uses per-service endpoint ranges so the private
probe can validate each hostname against the correct subnet, rather than a
single demo CIDR. The VM remains opt-in. Metadata alone does not establish
endpoint approval, resolver readiness, policy completion or runtime connectivity.
For older state without these outputs, use the reviewed output-update procedure
below with **both** the original ownership inputs and private-access profile.

### Probe compatibility

Terraform supports more model APIs than the supplied test scripts. Both
`Test-ModelAliases.ps1` and `Test-PrivateGateway.ps1` test **every** alias through
`/default/models/openai/v1/chat/completions`. They require each alias to declare
`api_format = "OpenAIChatCompletions"` and include
`"/openai/v1/chat/completions"` in `endpoints`. The new
`model_api_configuration` output carries these values; incompatible or missing
metadata stops the test rather than skipping a model.

This is a necessary compatibility check, not proof that a model accepts every
parameter. The public test sends `messages` and expects `choices[0].message.content`.
The private test additionally uses `max_tokens = 8`, `temperature = 0`, and expects
the exact reply `OK`. The example GPT-4.1 models are the reference configuration.
Do not assume a reasoning model supports those parameters just because it exposes
Chat Completions.

For Responses-only models, embeddings, image generation or other APIs, supply a
model-specific test on the **same intended network path**, with the documented
request/response format and explicit success criteria for every alias. Do not
change the declared endpoints just to bypass this check. A format/parameter
rejection, content mismatch, quota error or token-limit `429` is not by itself a
DNS/private-network failure.

**Existing state without the new output:** use the normal reviewed plan/apply
flow with the unchanged input file and, for private deployments, the explicit
private profile and selected network-ownership inputs. An output-only update
should contain no resource actions. Stop if unexpected resource changes appear;
do not replay an old plan or apply an
unrelated repair just to run a test. These instructions do not refresh or modify
your existing state automatically.

## Networking

The [private connectivity path](private-connectivity.md) has two network/DNS
ownership modes, independent of Public/Private-only exposure:

| Mode | Foundation ownership | Workload behavior |
| --- | --- | --- |
| `create` (default) | Sample-managed VNet, subnets, NSGs, private DNS zones and links | Keeps existing resource names, Terraform addresses and address defaults; creates private endpoints and zone groups. |
| `existing` | Platform-owned VNets, subnets, NSGs, UDRs, firewall, resolver, DNS zones and links | Reads subnet/VNet metadata, joins approved subnets, creates new private endpoints, and manages zone groups only when selected. |

The table describes behavior **with private networking enabled**; an ownership
profile alone does not activate it. The create foundation is **not** a corporate
hub/firewall/landing-zone deployment.
Network and DNS remain logically separate, but the supported modes pair their
ownership; create-network/external-DNS hybrids are not implemented.

Both modes create gateway (`Gateway`) and model (`account`) private endpoints.
The four core zones are `privatelink.azure-api.net`,
`privatelink.cognitiveservices.azure.com`, `privatelink.openai.azure.com` and
`privatelink.services.ai.azure.com`. Optional Blob and registry endpoints require
their additional subnet/zone inputs in existing mode; see the
[field and DNS-key table](private-connectivity.md#existing-network-prerequisites).
No mode imports pre-existing private endpoints or adopts existing application,
model or resource-group resources.

Tested gateway contract: `2025-09-01-preview` with `virtualNetworkType = "External"`.
Inbound Private Link and outbound integration solve different problems. Neither replaces the other.

Existing-mode AzAPI reads use actual **IPv4** subnet CIDRs, delegations, gateway
NSG attachment and parent VNet locations. The gateway integration subnet must
be in `gateway_location`, delegated to `Microsoft.Web/serverFarms`, at least
`/27`, and have an approved NSG attached. Missing attachment fails the full
plan; existing mode does not create, adopt or modify the NSG. Its effective
rules and routing still need [platform-owner checks](private-connectivity.md#confirm-the-gateway-subnets-network-security-group).
An enabled agent
integration subnet must be delegated to `Microsoft.App/environments` and in
`location`, at least `/27` and wholly within RFC1918 IPv4. RFC1918-only is this
sample's supported address-space subset, not a universal platform restriction;
see the [agent subnet requirements and source](private-connectivity.md#existing-network-prerequisites).
Never use either delegated integration subnet for private endpoints.
Per-service endpoints and the optional client can use separate approved VNets;
their location follows their own subnet's VNet, not the demo gateway VNet.

Endpoint subnets must belong to `subscription_id`. The sample's new private
endpoints remain workload-resource-group-owned, and Azure requires a private
endpoint and its VNet to share a subscription and region. Other resource
groups/VNets/regions within that subscription are allowed; central DNS zone IDs
may belong to another subscription. Cross-subscription endpoint placement or
ownership is a separate extension, not implemented here. See the
[prerequisites and Azure constraint](private-connectivity.md#existing-network-prerequisites).

Existing mode never edits central subnet policies or assumes direct DNS links
from each spoke. `workload` zone-group management needs explicit permissions to
associate the endpoints with the supplied zones. `platform` omits those groups
and does not manage central records/links or wait for policy: the platform must
complete DNS integration before private calls or agent use. Terraform success
does not prove resolver/runtime connectivity. Scope deployment read/join,
private-endpoint/approval and DNS permissions to the intended resources; do not
prescribe broad grants to make a plan succeed.

The optional Ubuntu VM has no public IP and has a narrow custom role for reading
the gateway key. In create mode its NSG denies inbound traffic and its subnet
allows outbound internet for VM agent/ARM operations, so it is not air-gapped.
Existing mode requires an explicit approved `client_subnet_id` in workload
`subscription_id`: the VM, NIC and VNet must share subscription/location.
Your existing NSG/UDR/egress controls are retained; the sample does not open them for the VM.
An approved existing private client can be used instead.

**Not configured:** corporate DNS forwarding, peering, VPN, forced tunneling
and custom firewall rules. The platform must supply these where required.
Review the [official networking guide](https://learn.microsoft.com/azure/api-management/ai-gateway-configure-private-networking)
for same-region integration subnets, DNS and NSG requirements.

Changing an existing `create` deployment to `existing`, or disabling private
networking, can propose removal of sample-managed resources. The created VNet
has a `prevent_destroy` guard; do not bypass it for a mode change.
DNS zones have no blanket guard, so review deletion of optional sample-managed
zones/links when disabling their features.
This is not an automatic migration. Keep the authoritative state/backend and
seek a separate reviewed state/migration plan; never copy state or import the
same resource into a second owner. The core private path does not isolate the
original agent account or ACR. Private hosted agents and Storage are separately
opt-in, as described above.

Changing workload/platform DNS zone-group ownership likewise requires a reviewed
state handoff, not a routine flag flip or automatic ownership transfer.
Private-endpoint subnet changes trigger replacement of the affected endpoints,
alongside the existing service-target replacement behavior; repeat approval,
DNS and runtime checks after an approved replacement. Moving existing
gateway/agent integration or client subnets is a separate migration, with no
automatic VM/NIC relocation.

### Legacy gateway private endpoint approval and cleanup

These implementation and repair notes are **not** new-deployment steps.
For normal execution use the [private procedure](private-connectivity.md);
for deployed gateways use its [existing-private entry](private-connectivity.md#existing-private-deployments).

The gateway endpoint uses a manual request followed by explicit APIM connection
approval. With workload-managed DNS, Terraform waits for approval before
creating its DNS zone group. With platform-managed DNS, central automation owns
the association; Terraform does not wait for it.

Approval verifies that the service-created connection belongs to the expected
endpoint. An explicit PUT action preserves the required body `id`; the legacy
API rejects ordinary update-resource requests that omit this field.
Already-approved connections use GET because the API also rejects redundant
approval. After approving a newly Pending connection, a subsequent reviewed
plan/apply records this read-only GET state before final drift verification.
It does not recreate the endpoint or change approval.

This avoids an observed legacy auto-approval failure, `PrivateConnectionNotFound`,
where Network expects a generated connection name but APIM stores the
caller-supplied name. `Approved` alone is insufficient: wait for asynchronous
completion and both provisioning states, check private DNS and prove inference
from the selected private client. See the
[official Pending/Approve sequence](https://learn.microsoft.com/azure/api-management/ai-gateway-configure-private-networking).

The manual profile selects the separately named `-gateway-manual-pe`.
Switching the approval flag replaces the gateway endpoint, not the gateway
service or model endpoint. Retain an existing healthy automatic endpoint only
with the approved `-var=gateway_private_endpoint_manual_approval=false`
exception after the profile on **every** plan. Use
[input composition](../deployment.md#compose-the-inputs); never import a new
endpoint over old state without preserving state and accounting for the old
cloud resource.

**Observed cleanup caveat:** the legacy service can retain an APIM connection
record after its failed Network endpoint and NIC have been deleted. In the
observed repair, deleting that orphan or first rejecting it returned asynchronous
`UpdateApiServiceFailed`; the approved replacement kept working.
Follow the operation's polling URL: initial `202` is not successful cleanup.
Verify the old endpoint/NIC are absent and the replacement still passes private
inference. Record the residual APIM reference rather than repeatedly retrying or
rebuilding the gateway. A zero-drift plan does not prove that unmanaged reference
has disappeared.

## Optional Terragrunt adapter

**Who:** the Terraform/Terragrunt platform maintainer. If the operator does not
maintain that pipeline, ask its maintainer to adapt this section. Do not build a
second deployment system. Without Terragrunt, retain the
[direct input-file workflow](../deployment.md#compose-the-inputs).

[terragrunt-existing.hcl.example](../examples/terragrunt-existing.hcl.example)
consumes separate network and DNS dependencies and uses this **same standalone
Terraform root from a local checkout**, not unpublished remote feature code.

### 1. Identify the existing live units and workload state

The following is an **illustrative layout**. `platform-live` represents the
existing deployment-configuration repository; `live` does not mean production-only.
Retain existing folders, input-file names, include labels and backend/state
configuration. No renaming or recreation is required.

```text
C:\work\gateway-source\ai-gateway_test\samples\terraform\  approved clean source
C:\work\platform-live\
  root.hcl                    existing include/auth/backend conventions
  network\terragrunt.hcl       existing, applied network unit
  dns\terragrunt.hcl           existing, applied central-DNS unit
  ai-gateway\
    terragrunt.hcl            adapted copy of the supplied adapter
    workload.tfvars           approved non-network workload inputs
```

Confirm which existing `root.hcl` and backend/state key belong to this workload.
For a new gateway, use its approved new workload unit; for an already managed
gateway, do not introduce a second unit/state owner. The network and DNS units
remain independent. The sample does **not** create `root.hcl`, choose a backend
or migrate any state.

### 2. Confirm available outputs before editing the adapter

Ask the platform maintainer to inspect only the relevant outputs through the
existing platform pipeline. No full state export is needed. The dependency
units must already be applied and readable by the approved runner.

| Dependency | Expected outputs |
| --- | --- |
| `network` | `gateway_subnet_id` (string), `endpoint_subnet_ids` (map containing `gateway` and `models`) |
| `dns` | `private_dns_zone_ids` (map containing `gateway`, `cognitiveservices`, `openai`, `services`) |

Each value is a **full resource-ID string**, not a resource name or a whole
subnet/zone object. If the platform uses other output names, change the adapter's
right-hand-side expressions to the real outputs. For example, only if the
existing module actually exposes that map/key:

```hcl
gateway_subnet_id = dependency.network.outputs.subnet_ids["gateway-integration"]
```

This is one field **inside** `inputs.existing_private_network`, not a new
top-level Terraform variable. The four DNS keys still map to the exact zone
names in the [ID lookup table](../deployment.md#find-resource-ids-and-fill-in-the-network-input-file).
Missing output or `Unsupported attribute` means stop and correct the contract
with its owner; do not fill deployment dependencies with fake `mock_outputs`.

### 3. Place and adapt the two workload files

Copy the supplied adapter into the approved workload unit as `terragrunt.hcl`
**only if that file does not already exist**. For an existing file, the
maintainer integrates the blocks through the usual review process instead of
overwriting its settings. Create/select that unit's protected `workload.tfvars`
using the [base input catalogue](../deployment.md#inputs-and-state), without
copying another deployment's state.

| Adapter field | What to set for the illustrative layout |
| --- | --- |
| `include "platform"` | Retain the approved parent include and its label. `find_in_parent_folders("root.hcl")` is correct only when that is the existing platform convention. |
| `locals.sample_root` | `"C:\\work\\gateway-source\\ai-gateway_test\\samples\\terraform"` for the approved clean source checkout. Record its exact commit and keep deployment tfvars/state out of it. |
| `dependency "network".config_path` | `"${get_terragrunt_dir()}\\..\\network"` for the existing network unit. It is not a subnet ID. |
| `dependency "dns".config_path` | `"${get_terragrunt_dir()}\\..\\dns"` for the existing DNS unit. It is not a zone ID. |
| First `extra_arguments` var-file | The approved workload input file, shown here as `workload.tfvars`; retain an existing filename and any additional runtime input files before the access profile. |
| `inputs.existing_private_network` | Map the verified platform outputs, preserving the required nested field names and complete object. |
| `private_dns_zone_group_management` | `workload` only with agreed permissions; `platform` only when central automation owns the associations. |

HCL quoted Windows paths use `\\`. Save the edited file. Check **the live
repository's** ignore rules for inputs, plans, cache and evidence: this sample's
`.gitignore` does not protect a different live repository.

Keep network-ownership fields out of `workload.tfvars` and inherited var-files:
explicit Terraform var-files can override Terragrunt `inputs`. Do **not** also
load the placeholder `network-existing.tfvars.json`. The adapter already obtains
those IDs from dependencies. Later whole-object assignments do not deep-merge
with them. Inspect inherited extra arguments/environment and all runtime files
with the pipeline owner; the visible block may not be the complete configuration.

### 4. Use the existing pipeline, for this workload unit only

The adapter selects **final private-only posture**, not a verified
private-from-first-create bootstrap. Resolve the same
[monitoring](monitoring.md#choose-the-current-access-state), temporary-access
approval and DNS readiness gates as the direct path before running a full plan.
Do not silently remove the private profile to get a new deployment through.
Existing gateways retain their current approval mode and approved exceptions.

From the approved workload live-unit directory, the maintainer can use the
installed Terragrunt version's normal plan job. The current CLI supports
[`run --`](https://docs.terragrunt.com/reference/cli/commands/run/); the equivalent
single-unit saved-plan example is:

```powershell
Set-Location 'C:\work\platform-live\ai-gateway' # Replace with the approved live unit.
terragrunt --version
$planPath = 'C:\protected-evidence\gateway\terragrunt-private.tfplan'
terragrunt run -- plan -input=false "-out=$planPath"
if ($LASTEXITCODE -ne 0) { throw 'Terragrunt workload plan failed.' }
terragrunt run -- show $planPath
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the Terragrunt workload plan.' }
```

Use the approved, existing restricted artifact folder; do not invent a new
backend or upgrade Terragrunt for this example. Terragrunt can initialize/read
backends and execute inherited hooks even for a plan, so this is a
**target-authorized pipeline operation**, not an offline syntax test.
Do not run `--all`/`run-all` or apply the network/DNS units to install the gateway.

Review the [same ownership/access checklist](../deployment.md#review-every-plan-before-apply).
Then use the normal approval and saved-plan apply job for **this workload**,
preserving its exact source, backend and artifact. The platform maintainer owns
the installed version's cache/artifact and
[extra-argument handling](https://docs.terragrunt.com/features/units/extra-arguments/);
do not guess a `.terragrunt-cache` path or start plain Terraform in the live unit.

The sample's PowerShell helpers run Terraform relative to their own source
directory; they do not automatically locate a Terragrunt unit/cache or inherit
its input arguments. The maintainer must integrate output/drift/test execution
with the **same configured module and state** and record source provenance.
Until that integration exists, use the manual acceptance steps through the
approved pipeline, adapting the output commands there. Do not run a helper
against the clean source checkout or copy state to make it work.

**Expected handoff:** mapped real outputs, one approved workload owner/backend,
a reviewed plan with no central-network changes, and a named pipeline/test
operator. Pipeline integration and live connectivity remain work for that
operator; this adapter is not a separate turnkey deployment system.

## State and security

- **Backend choice:** this root does not configure a shared remote backend.
  Initialization without backend configuration uses local state; allow that only
  for an explicitly approved local PoC. For a new shared workload, obtain the
  platform's approved encrypted, access-controlled backend and locking procedure
  before initialization. Follow [state ownership and initialization](../deployment.md#1-confirm-which-state-belongs-to-this-workload).
- **Existing workloads:** retain the authoritative backend, state and approved
  initialization procedure. `terraform init -migrate-state` is **not** a routine
  setup step; any migration or reconfiguration needs a separate reviewed plan.
  Do not initialize a second state or copy/import platform resources into this one.
- State and plans can contain sensitive data, including telemetry connection
  strings. Restrict access and never commit them. `.gitignore` covers state,
  plans, provider downloads and user `.tfvars`.
- Storage blocks anonymous blobs and shared keys. ACR admin users and Foundry local auth are disabled. Gateway payload capture is disabled.
- Keep policy-required storage restrictions. Private hosted-agent storage access is **not** verified here.
- Project roles mirror the upstream Bicep, including Cognitive Services Contributor. Developer access also grants Storage Blob Data Contributor. Enable it on purpose and review least privilege.

### Single-group consolidation

The root module now manages only `azapi_resource.resource_group["gateway"]`,
retaining its existing `rg-<environment_name>-<resource_token>-gateway` name.
Models, agents, Storage, ACR and both monitoring stacks share that group with
the gateway and optional network/test client. Child resources remain under their
service parents, and the custom role definition remains subscription-scoped with
only this group as its assignable scope. Region inputs are still independent;
sharing a group does not move resources to a different region.

**Monitoring exception:** gateway OTLP enablement also provisions linked,
Azure-managed monitoring resources/groups. The exact DCR-scoped publisher role
can live outside the application group. Final acceptance verifies the linkage,
managed-group owner, gateway principal and exact role; a managed-looking name
alone is never an exemption. See [monitoring ownership and setup](monitoring.md).

The legacy gateway has `prevent_destroy = true`: a replacement/destroy plan must
fail rather than silently remove a resource whose recreation is not guaranteed.
The October 27 rehearsal created the original SKU in one eligible environment;
it did not establish future recreation or availability in every subscription/region.
Keep the existing environment, location inputs and authoritative state. Do not
discard state or change the environment label to get a "fresh" gateway.

For an existing three-group deployment:

1. Preserve a protected state backup and coordinate all Terraform writers.
2. Review a fresh **full** plan with the original inputs and the explicit private
   profile. Changed parent IDs normally require backend replacements; removing
   the old group instances from the configuration also proposes their deletion.
   This code change does not perform an Azure resource move.
3. Choose and approve a supported resource move or a deliberate rebuild before
   applying. Generic CognitiveServices move support does not establish support
   with private endpoints. Rebuilds can lose Storage data, registry images and
   telemetry history. Existing global names and soft-deleted Foundry backends can
   prevent recreation; resolve these explicitly, never by automatic purge.
4. Reconcile changed identities, resource-scoped roles, connection IDs and private
   endpoint targets. A private endpoint cannot change its target service in place.
   The replacement trigger covers known target changes, but AzAPI 2.13 skips
   reference triggers when its body contains unknown values, including a newly
   recreated account's ID. For this consolidation, the full plan **must** include
   `-replace='azapi_resource.private_endpoint["models"]'` alongside the explicit
   private profile. Confirm the Models endpoint is replaced, not updated, before
   approving any apply. Preserve the AIGateway API/authentication and network
   settings. Reject any unexpected gateway or network replacement.
5. Verify private inference and telemetry before cleanup. **Do not apply a plan
   deleting either old group** until every contained resource is accounted for
   and its removal is approved. Azure group deletion can remove resources not
   tracked by Terraform. A successful but empty generic inventory is not enough
   when direct resource GETs still find resources.

The legacy `resource_groups` output keys remain available for scripts, but now
resolve to the same name. A plan against the old layout is not an output-only
update. Offline tests establish placement and contracts, not migration safety.

For an approved rebuild, set a stable `backend_revision` in your deployment
inputs to generate fresh backend names without changing the gateway or group.
Keep that revision for subsequent deployments; changing or removing it causes
another replacement. The default empty revision preserves existing names.

Set `retain_legacy_resource_groups = true` only during migration to keep the old
groups managed until backend acceptance. It does not place any new service in
those groups. After verifying their contents and approving cleanup, set it back
to `false` and review a new full plan before applying the two group deletions.
The normal final configuration manages exactly one group.

## Offline checks

No Azure resources or authentication needed. Use a clean checkout without
deployment tfvars/state and record its approved immutable commit. The local/CI
entrypoint includes every regression suite. Run from `samples\terraform` with
PowerShell 7, Terraform 1.11.4 and Python 3.12+:

```powershell
.\scripts\Test-Offline.ps1
```

This uses `init -backend=false` with the committed provider lockfile in readonly
mode, checks formatting/validation, and runs mocked Terraform and script suites.
It writes local initialization/test files and may download providers; "offline"
means no Azure operations, **not** network-free or read-only. It does not migrate
an existing backend. CI runs the same command on Windows without Azure secrets,
OIDC permissions or pull-request cloud deployment. Operators can retain the
approved revision's CI result instead of rerunning maintenance fixtures.

The Terraform tests use mocked AzAPI; script tests stub network/CLI calls. They
check shared-group placement, preserved monitoring/output contracts, model/API metadata and token-limit wiring, gateway location, identity-based
backends, opt-in developer roles, invalid inputs, the private profile, and rejection
of unsupported probe APIs. Python 3 and PowerShell 7 are required for the script
tests. These are **not** runtime tests. For actual acceptance, use the
[deployment acceptance guide](acceptance.md).

## Implementation notes

### Terraform implementation

> [!IMPORTANT]
> **Terraform Registry disclaimer (checked October 25, 2026):** No dedicated
> Microsoft-published Registry module was identified for this standalone
> `AIGateway` preview. The [general API Management AVM](https://registry.terraform.io/modules/Azure/avm-res-apimanagement-service/azurerm)
> and community gateway modules are not the same as a dedicated module for this
> preview. This is a repository-specific root configuration, not an official
> Registry module to install.

A **module** packages reusable Terraform configuration; a **provider** implements
communication with Azure. This configuration uses Microsoft's
[AzAPI provider](https://learn.microsoft.com/azure/developer/terraform/overview-azapi-provider),
declared as `Azure/azapi` in [versions.tf](../versions.tf), not a custom provider
or gateway-specific module.

[ai-gateway.tf](../ai-gateway.tf) declares `azapi_resource` with
`Microsoft.ApiManagement/service@2025-09-01-preview`, SKU `AIGateway` and explicit
child-resource API versions. AzAPI sends these definitions to Azure Resource
Manager (ARM); Terraform manages state and dependencies. The documented
[AzureRM API Management SKU list](https://registry.terraform.io/providers/hashicorp/azurerm/5.11.0/docs/resources/api_management)
does not include `AIGateway`; that is distinct from saying Terraform cannot
deploy it. See [resource type and lifecycle](#resource-type-and-lifecycle)
before considering any deployment or migration.

Some preview child resources are absent from AzAPI's bundled schema, so their
local `schema_validation_enabled` check is selectively disabled. This does
**not** bypass Azure API validation, RBAC or Azure Policy. API contracts remain
explicit sample-maintenance responsibilities; validation/mock tests cannot
prove Azure will accept a deployment. No provider/SKU upgrade follows from
the separation of root files.

- Follows the upstream [Bicep infrastructure](https://github.com/Azure-Samples/simple-foundry-hosted-agent-python-aigateway/tree/c572db847e4bff5278bc5f8630c2acb4b6991119/infra) and a [model-registration fix](https://github.com/Azure-Samples/simple-foundry-hosted-agent-python-aigateway/commit/03fcd3788aea06cf6000af19890f8164303348d5).
- AzAPI defines the preview ARM resources directly. Model operations are serialized per account with locks. The automatic gateway `default` workspace is referenced, not recreated.
- Token policies use `["identity"]`, not the older scalar `"Identity"` key.
- AzAPI 2.13 has no bundled schemas for several preview resources, so those blocks set `schema_validation_enabled = false`. ARM still validates them at deploy time. Offline success does not prove preview access, capacity or API acceptance.

## Limitations

General constraints checked **October 19, 2026**; resource-type lifecycle below
checked **October 25, 2026**. Preview features can change. Recheck the official
sources before changing or replacing a deployment.

### Resource type and lifecycle

This sample keeps `Microsoft.ApiManagement/service@2025-09-01-preview` with SKU
`AIGateway`. Confirm deployment availability for that exact resource type, SKU,
subscription and region. An observed successful deployment and Microsoft's
published support/lifecycle guidance are different evidence; neither should be
replaced by a blanket claim about all AI Gateway deployments.

The [Microsoft migration guide](https://learn.microsoft.com/azure/api-management/ai-gateway-resource)
documents a transition to `Microsoft.ApiManagement/aigateways` and a
**January 15, 2027** lifecycle deadline for the earlier representation.
The replacement is a different resource type, not an in-place API-version edit;
the guide currently lists gateway private endpoints as unsupported on that
replacement. The private networking documented here uses the `service` /
`AIGateway` contract. No resource-type migration or SKU change is implemented
by this sample.

### Microsoft-documented constraints

- **AI Gateway preview:** best-effort, **no SLA**. APIs, limits, regions and pricing can change. Documented regions include East US 2 and Sweden Central, with access varying by subscription. ([overview](https://learn.microsoft.com/azure/api-management/ai-gateway-overview))
- **Hosted-agent VNet injection is set at account creation** and cannot be added later. Enable the [private hosted-agent configuration](private-hosted-agent.md) from the start for new agent accounts. A separately deployed agent passed the private gateway/model path on October 25; application deployment, runtime roles and acceptance remain required for each new environment. ([Foundry networking limits](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks#limitations))
- **Private endpoints can be added later** to an existing legacy `service`/`AIGateway` resource, with outbound integration configured separately. Private endpoints alone do not give the gateway or agents outbound access. This does not establish support on the replacement `aigateways` resource. ([private networking](https://learn.microsoft.com/azure/api-management/ai-gateway-configure-private-networking))
- **Private ACR image pulls** are supported for Foundry projects created after June 25, 2026. Older projects need public ACR reachability. This sample leaves ACR public.

<a id="known-blocker-private-only-gateway-ingress"></a>

### Private-only gateway ingress status

**Terraform creation and staged closure passed in an isolated rehearsal
(October 27, 2026, Sweden Central).** A new original `service` / `AIGateway`
(capacity 1) was created with separately owned platform/network, central DNS and
runtime-access states. It reused a central resolver and firewall; the workload
owned its private endpoints/zone groups, not those foundations. Temporary public
bootstrap was approved and closed in stages through Terraform.

Both `gpt-full` and `gpt-mini` returned private-route HTTP 200 / OK; missing and
invalid keys returned authentication-specific 401 on that route. Valid-credential
public gateway and direct-model calls returned network-specific 403, with prior
same-resource positive controls retained. Actual gateway/model/storage public
access was Disabled. Each positive trace had a successful server span and
correlated logs; fresh scoped token metrics and both intended firewall traffic
legs passed. Four full refreshed plans returned no changes (platform 30, DNS 11,
workload 38, runtime access 2 managed resources).

The rehearsal exposed an existing-subnet NSG prerequisite and an AzAPI 2.13.0
null/unknown approval-body planning issue; both received focused source fixes.
The approval action now retains a non-null body, still uses read-only GET when
Approved and PUT only when Pending, and retains exact endpoint/status safeguards.
The final closure made two updates and no creates/deletes; an earlier failed
model endpoint was replaced only after explicit approval.

This proves the tested original-SKU deployment and staged update, **not**
private-from-first-create, universal region/subscription support, your
remote backend/CI/PIM/policy implementation, Blob/registry operations or hosted-
agent execution. It used a separate private client without workload state or
transported keys. The documented PowerShell 7/Azure CLI handoff examples are
not the exact PowerShell 5.1/managed-identity commands used in that live test.
The original October 25 agent proof and its portal review remain separate.

**Configuration blocker resolved for the observed gateway (October 25, 2026).**
The operator disabled public access in the portal. Completion took a long time
(no measured duration captured). A subsequent read-only ARM GET confirmed
`publicNetworkAccess = Disabled`, `provisioningState = Succeeded`, and the
gateway private connection `Approved` / `Succeeded`. Outbound integration
remained `virtualNetworkType = External`; that value does not mean public
ingress is enabled.

That October 25 finding is a successful portal update, **not** evidence that a new gateway can be
created private-only, that the earlier Terraform/CLI update failure is fixed,
or that every subscription/region behaves identically. The separately documented
legacy-resource lifecycle restrictions remain unchanged. The later October 27
Terraform evidence above has its own explicit scope; it does not establish the
cause of the earlier service failure.

**Observed in tests, not a universal SKU limit.** Microsoft [documents disabling public access after private connectivity is verified](https://learn.microsoft.com/azure/api-management/ai-gateway-configure-private-networking#inbound-private-link). In the **October 18, 2026, Sweden Central** tests:

- Both aliases passed private DNS and inference checks with model public access disabled (ACL Deny).
- Disabling gateway public access failed with `UpdateApiServiceFailed`, through both Terraform and the CLI's public-access PATCH. Private access kept working, but public access stayed on.
- A minimal gateway in the same subscription and region reproduced the failure. Its private endpoint still worked. Test resources were deleted.

Those failures and the October 23 product-group investigation are historical
observations, not a current prohibition against `Disabled`. Their root cause
is still unknown; do not attribute success to a timeout change or product fix.

Use the explicit [private-only profile](../profiles/private-only.tfvars.json)
for the intended end state. Keep it as the final access var-file on all plans,
including monitoring and drift checks, followed only by approved endpoint
compatibility exceptions. The intermediate provisioning profile still sets `Enabled`.
For an already-disabled gateway, align inputs and inspect a fresh plan without
reopening public access or reusing a saved pre-change plan.

**Subsequent private-agent proof completed on October 25, 2026:**

A fresh agent Responses call returned **OK**. The exact trace contained gateway
and model-backend **HTTP 200** for `gpt-mini`. An authenticated public gateway
call returned an explicit **HTTP 403 public-network denial**. Gateway, model and
new Foundry public access stayed disabled, temporary executor roles were removed,
the VM was deallocated and the final Terraform plan had no changes.
See the [private-agent reference](private-hosted-agent.md#observed-deployment-and-proof).
This verifies the tested path, not universal SKU behavior, every alias, Entra
caller authentication or every preview agent ingress surface.

**Repeat these gates for each new environment or relevant change:**

1. Every alias succeeds from a private client, with current private DNS evidence.
2. A previously working valid-credential public call gets a network-boundary
   rejection. A 401, authentication-specific 403, timeout or DNS failure alone
   does not prove this. Record the public test location and actual response.
3. The selected end-state plan has no pending changes.
4. Any required hosted-agent path and fresh telemetry are verified separately.
   Use a fresh session/version and correlate its exact gateway/backend trace.

The acceptance runner checks the selected ARM posture and (when requested)
private runtime/telemetry; it does **not** test public network rejection or
certify private-only runtime isolation. No automatic recovery, Azure mutation
or destructive workaround is included in that runner.

## Cost and cleanup

Both paths create billable resources. Model calls, Premium ACR, Storage and
monitoring all cost money. Deallocate the optional VM as described in
[private connectivity](private-connectivity.md#step-6-stop-the-vm-when-you-are-done);
stopping the VM does not stop the other charges.

The gateway has `prevent_destroy = true`: an ordinary full `terraform destroy`
is intentionally blocked. Do not remove this protection, remove resources from
state or delete the group to work around it. This legacy gateway might not be
recreatable. Full teardown needs explicit approval for permanent gateway/data
loss, exact resource inventory (including resources not managed by this state),
state backup and a separately reviewed protection change and destroy plan.
Keep the private profile and all original inputs on that plan. If retaining the
gateway, design and review a partial teardown with its owner instead; there is
no universally safe one-command cleanup. Acceptance automation never destroys
resources or removes the protection.

## References

- [Upstream Bicep infrastructure](https://github.com/Azure-Samples/simple-foundry-hosted-agent-python-aigateway/tree/c572db847e4bff5278bc5f8630c2acb4b6991119/infra)
- [AzAPI provider](https://registry.terraform.io/providers/Azure/azapi/latest/docs)
- [AI Gateway overview](https://learn.microsoft.com/azure/api-management/ai-gateway-overview)
- [AI Gateway private networking](https://learn.microsoft.com/azure/api-management/ai-gateway-configure-private-networking)
- [Foundry Agent Service networking](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks#limitations)
- [Model and tool management](https://learn.microsoft.com/azure/api-management/ai-gateway-manage-models-tools)
