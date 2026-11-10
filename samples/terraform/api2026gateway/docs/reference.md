# Standalone AI Gateway reference

[Start-to-finish guide](../README.md) · [Architecture explanation](architecture.md) · [Terraform overview](../../README.md)

This reference describes this checkout's configuration, not live service
acceptance. The entry is a separate Terraform root calling the shared
implementation as `module.gateway` with `source = "../"`.

## File map

| File | Responsibility |
| --- | --- |
| [../main.tf](../main.tf) | Select the standalone resource family, load the default profile and call the shared module |
| [../versions.tf](../versions.tf) / [../.terraform.lock.hcl](../.terraform.lock.hcl) | Entry requirements and pinned provider selection |
| [../variables.tf](../variables.tf) | Supported typed inputs |
| [../legacy-input-guards.tf](../legacy-input-guards.tf) | Reject legacy settings explicitly rather than silently ignoring them |
| [../terraform.tfvars.example](../terraform.tfvars.example) | Starting input template |
| [../model-profile.json](../model-profile.json) | Pinned deployment and alias defaults |
| [../examples/model-routing.tfvars.example](../examples/model-routing.tfvars.example) | Optional, illustrative replacement maps; never auto-loaded |
| [../outputs.tf](../outputs.tf) | Described IDs, endpoints and review metadata; no runtime key value |
| [../../main.tf](../../main.tf) | Deterministic names, default three-group or optional fresh single-group ownership or existing-group reuse, and API selection |
| [../../ai-gateway.tf](../../ai-gateway.tf) | Gateway and its readiness check, endpoint, runtime key and retained legacy connector compatibility |
| [../../model-routing.tf](../../model-routing.tf) | Model provider, catalog policies and aliases |
| [../../mcp-tool-servers.tf](../../mcp-tool-servers.tf) | Optional remote MCP tool-server registrations and their per-caller rate limit |
| [../../gateway-policies.tf](../../gateway-policies.tf) | Optional gateway-wide client IP allow list merged into the `default` workspace policies |
| [../../foundry-models.tf](../../foundry-models.tf) | Foundry model account, deployments and explicit backend safety binding |
| [../../foundry-agents.tf](../../foundry-agents.tf) / [../../rbac.tf](../../rbac.tf) | Agent-support resources, connections and scoped identity bindings |
| [../../monitoring.tf](../../monitoring.tf) | Log Analytics, Application Insights and telemetry exporter |
| [../../ai-gateway-backend.tf](../../ai-gateway-backend.tf) | Select the owned or external outbound subnet and read external subnet/VNet metadata |
| [../../api2026-private-network.tf](../../api2026-private-network.tf) | Opt-in owned backend network, private endpoints, DNS and AMPLS |
| [../../api2026-private-client.tf](../../api2026-private-client.tf) | Opt-in verification VM, identities, scoped grants, Blob container and diagnostic |
| [../../versions.tf](../../versions.tf) | Shared provider configuration; unchanged for both entry points |

Terraform loads all `.tf` files in a module together. File extraction does not
change resource addresses or create new modules; these filenames express
responsibilities, not deployment order.

## Resources and identities

| Group | Resources in this entry |
| --- | --- |
| Gateway | Standalone AI Gateway without an explicit SKU override, Foundry provider, model catalog registrations, aliases, optional MCP tool servers (the entry default registers Microsoft Learn), optional gateway-wide IP allow list, `default` runtime key, Log Analytics, Application Insights and exporter |
| Models | Separate Foundry model account and selected deployments bound to the existing system-managed `Microsoft.DefaultV2` safety policy |
| Agents | Separate agent account and project, Storage, Premium Registry, agent Log Analytics/Application Insights and connections |

Names and group ownership are derived deterministically from the configured
workload inputs. Three managed resource groups are the default. For **fresh
state only**, `api2026_resource_group_name` selects one exact managed group for
all three logical workloads; it is not an existing-state consolidation option.
Adding `api2026_existing_resource_group = true` instead reuses that group,
which must already exist, without owning it; see
[state and lifecycle](#state-and-lifecycle).
The parent legacy root retains its own one-group behavior.
No connector gateway is created for the API-2026 contract.

1. A caller uses a gateway API key or deliberately configured Entra access.
   The optional `gateway_access_principals` grants are additive; they do not
   disable key authentication.
2. The gateway's managed identity receives model-account access and authenticates
   to Foundry backends. Alias routing chooses a catalog registration, whose
   backend deployment key must exist in the complete model map.
3. The separate project identity receives agent-account and dependency roles
   through [rbac.tf](../../rbac.tf). It is not the gateway identity. Optional
   developer grants are additional access, not required runtime identity.
4. Gateway telemetry targets Application Insights/Log Analytics independently of
   inference routing. Agent-support connections do not mean an agent image has
   been built, hosted or tested.

The API2026 project Registry and AppInsights connections explicitly request
`isSharedToAll = false`. Verify actual readback rather than assuming the service
preserves these settings. API2026 AppInsights metadata uses the full component
ARM ID; only the legacy account connection retains name-form metadata. See
[project monitoring connection](#project-monitoring-connection).

### Caller authentication

The current [security and identity documentation](https://ai.gateway.azure.com/docs/security-identity)
separates **caller → gateway** authentication from **gateway → backend**
authentication. In this sample, the gateway's managed identity and model-account
permissions serve the backend leg; they do not grant a caller gateway access.

| Caller method | Contract |
| --- | --- |
| Gateway runtime key | Send `Authorization: Bearer <key>`, not the legacy `api-key` header. This credential grants gateway-wide access and is not recommended for production. |
| Microsoft Entra ID | Send a bearer token with audience `https://azure-api.net/aigateway`; the delegated user scope is `https://azure-api.net/aigateway/Data.All`. The caller also needs the required invocation authorization. |

Built-in Azure CLI and PowerShell clients do **not** require the custom-app
consent setup. That does not remove caller authorization requirements. Keep
caller tokens separate from ARM management tokens and backend credentials.
Optional `gateway_access_principals` bindings remain additive; this documentation
does not disable or remove the default key.
The key header and runtime hostname follow the
[standalone-resource contract](https://learn.microsoft.com/azure/ai-gateway/ai-gateway-resource).
Read `properties.frontend.defaultHostname` and prefix it with `https://`;
do not construct a hostname or fall back to the legacy `gatewayUrl` property.

## Inputs

Defaults, types and validations are in [variables.tf](../variables.tf); inherited
contract checks remain in [../../variables.tf](../../variables.tf).

| Inputs | Use |
| --- | --- |
| `subscription_id` | Required approved subscription identifier |
| `environment_name` | Workload name, default `api2026gateway`; choose deliberately because it affects deterministic names |
| `location` | Required approved Foundry/Storage/Registry/monitoring region; verify every selected model and quota there |
| `gateway_location` | Required approved standalone-gateway region |
| `tags` | Optional additional tags; the entry records its API contract |
| `api2026_resource_group_name` | Optional exact single group name for fresh state, created and managed unless `api2026_existing_resource_group` is `true`; `null` retains three groups; not a migration switch |
| `api2026_existing_resource_group` | Default `false`; `true` reuses the existing group named by `api2026_resource_group_name` instead of creating it; fresh state only; never toggle it on an existing state |
| `api2026_private_lab_enabled` | Default `false`; opt into the owned single-group backend network and verification client, not gateway private ingress or a hosted agent |
| `api2026_private_lab_ssh_public_key` | Fresh `ssh-ed25519` or `ssh-rsa` public key required exactly when the lab is enabled; no private key material or key generation |
| `gateway_backend_subnet_id` | Optional existing delegated subnet for creation-time outbound backend integration |
| `standalone_backend_public_network_access` | Optional `Enabled`/`Disabled` backend PaaS/monitoring override; `null` preserves defaults; `Disabled` requires the owned lab or an external outbound subnet and separately provisioned private connectivity |
| `model_deployments`, `model_aliases` | Optional complete replacement maps; `null` selects each checked-in default map |
| `model_allowed_client_cidrs` | Optional IPv4/IPv6 egress CIDR allow list for model calls; default `[]` emits no IP policy |
| `gateway_allowed_client_cidrs` | Optional gateway-wide IPv4/IPv6 egress CIDR allow list for models and MCP tool servers; default `null` leaves workspace policies unmanaged and `[]` removes the managed filter; see [gateway-wide IP allow list](#gateway-wide-ip-allow-list) |
| `mcp_tool_servers` | Optional remote MCP servers to register as gateway tool servers, keyed by name; the entry default registers the public Microsoft Learn server and `{}` registers none; see [MCP tool protection](#mcp-tool-protection-separate-extension) |
| `gateway_access_principals` | Optional named, typed Entra caller bindings; keys remain enabled |
| `developer_principal_id`, `developer_principal_type` | Optional explicit developer object ID/type; an empty ID creates no developer grants |

`tenant_id` is not a Terraform input in this entry. Authenticate in the approved
tenant and pass that tenant explicitly to the post-deployment configuration
checker; do not add an undeclared `tenant_id` to the input file.

Single-group names must start alphanumeric, contain 1–90 letters, digits,
underscores, parentheses, hyphens or periods, and not end in a period.
The owned lab requires that exact group, matching workload/gateway regions,
explicit backend access `Disabled` and no external `gateway_backend_subnet_id`.
Its SSH public key is rejected outside lab mode. See
[backend-private connectivity](#backend-private-connectivity) for the footprint.
`api2026_existing_resource_group = true` also requires a non-null
`api2026_resource_group_name` and is rejected with
`api2026_private_lab_enabled = true`, whose lab needs a group it owns. The
shared module also rejects it for the legacy contract.

Each `mcp_tool_servers` key is the tool-server name and endpoint namespace:
3–63 lowercase letters, digits or hyphens, starting and ending alphanumeric.
Each entry needs a non-empty `display_name` and an `https://` `url` without
user-info credentials. Validation does not detect secrets in the URL path or
query, so never put any there. `description` defaults to the display name.
`calls_per_period` (default 20) and `period_seconds` (default 60) must be whole
numbers of at least 1. The shared module defaults to `{}` and rejects tool
servers for the legacy contract.

**Legacy inputs are not supported here.** Omit `existing_private_network`,
`enable_private_networking`, `enable_private_test_client`,
`enable_private_hosted_agent`, `enable_storage_private_endpoint`,
`gateway_public_network_access`, `models_public_network_access` and
`storage_public_network_access`, along with
legacy private-client/network settings. The
[guard file](../legacy-input-guards.tf) is the authoritative list. Even a lone
`gateway_public_network_access = "Disabled"` or an explicitly supplied legacy
`false` flag is rejected; it does not make this a private deployment.

### Complete-map replacement

`model-routing.tfvars.example` is an optional illustration, not another required
layer. Replace **every** placeholder and confirm model, version, deployment SKU,
capacity and policy values for the target subscription. Its values make no
availability claim.

- A supplied `model_deployments` map replaces the entire default model map.
- A supplied `model_aliases` map replaces the entire default alias map.
- A supplied `mcp_tool_servers` map replaces the entire default tool-server
  map: include `microsoft-learn` to keep it beside other servers; `{}` registers
  none.
- Overrides are independent: overriding models alone does not rewrite the
  default aliases. Each alias backend must refer to a retained deployment key.
- When changing the profile, keep the complete coordinated maps together in the
  private approved inputs. Entries omitted from the replacement do not survive;
  an existing workload can therefore lose deployments or replace aliases.
- In a custom model map, `token_limit` remains required. Optional `cost_limit`
  and `request_limit` are omitted when absent/null; their default-profile values
  are not merged into custom models. Backend safety stays explicitly bound.
- `.tfvars.example` is not auto-loaded. If keeping a separate private routing
  file, pass it explicitly with a second `-var-file` at **plan** time, after the
  base input file, and review/apply the resulting saved plan.

## Pinned default profile

These are configuration pins, not “latest available” model claims or a quota
reservation. Confirm them before any live plan/apply.

| Deployment key | Model / version | Deployment capacity | Minute token policy |
| --- | --- | --- | --- |
| `gpt-latest` | `gpt-6.1-sol` / `2026-09-29` | 20 | 20,000 |
| `gpt-6-sol` | `gpt-6-sol` / `2026-09-22` | 20 | 20,000 |
| `gpt-mini-latest` | `gpt-5.4-mini` / `2026-03-17` | 200 | 200,000 |

All three select `OpenAI` / `GlobalStandard`, with
`OpenAIChatCompletions` and configured `/openai/v1/chat/completions` and
`/openai/v1/responses` endpoints. Deployment-capacity units are **not** gateway
token-policy units; do not assume a universal conversion.
`GlobalStandard` and a regional account alone do not establish EU-only
processing; separately confirm any processing-location requirements.

| Alias ARM key | Callable alias | Ordered backends |
| --- | --- | --- |
| `primary-router` | `gpt-latest` | `gpt-latest` priority 0 → `gpt-6-sol` priority 1 → `gpt-mini-latest` priority 2 |
| `mini-router` | `gpt-mini-latest` | `gpt-mini-latest` priority 0 |

Each configured weight is 100; weights express relative shares, not three
independent percentages. The policy defaults below apply to all three model
registrations. Model pins, capacities and alias routes are unchanged by this
governance bundle.

## Policies and backend safety

| Control | Default configuration | Where to change it |
| --- | --- | --- |
| Token limit | `tokenLimit`, minute window, `counterKey = ["identity"]`; counts in the profile table above | Per-model `token_limit`, positive integer |
| Monthly cost | `costLimit`, ID `monthly-caller-budget`, month window, amount 10, identity counter | Optional per-model `cost_limit`, positive amount |
| Request rate | `requestRateLimit`, 100 calls per 60 seconds, identity counter | Optional per-model `request_limit`, positive integer requests/minute |
| Model client IP allow list | Off by default; nonempty input adds `ipFilter`, `action = "Allow"`, to every model registration | `model_allowed_client_cidrs` |
| Gateway-wide client IP allow list | Off by default (`null`); a list adds one `ipFilter`, `action = "Allow"`, to the `default` workspace, covering models and MCP tool servers | `gateway_allowed_client_cidrs`; see [gateway-wide IP allow list](#gateway-wide-ip-allow-list) |
| Backend content filtering | Each Foundry deployment sets `raiPolicyName = "Microsoft.DefaultV2"` | Explicit binding in `foundry-models.tf`; not a gateway policy or a configurable opt-out |

These are inline JSON entries in each catalog model's `properties.policies`
(for the gateway-wide list, the `default` workspace's), not APIM XML or a
`/policies/policy` resource. They use the current
[portal policy catalogue](https://ai.gateway.azure.com/docs/policies);
that page also contains older contract examples. This entry retains its own
September 2026 resource paths. Catalogue exposure and offline tests do not prove
acceptance or enforcement on the exact API version.

Counters use the gateway's caller identity. A shared client key does not
establish separate per-person budgets. Do not infer isolated alias-level
counters or resets on failover. The monthly policy is **not an Azure spending
budget or billing cap**. Backend capacity/quota and gateway token/request limits
are separate; an upstream throttle can occur before a gateway limit. Controlled
enforcement checks must distinguish the two.

IP entries must be valid IPv4/IPv6 CIDRs, with `/32` or `/128` for individual
addresses; `/0` entries are rejected. Duplicates are removed and ranges are
sorted for stable configuration. Use the approved egress address observed by
the gateway, which can differ from a workstation address behind a proxy or NAT.
The sample does not discover or enable a caller range automatically. This is
**model-call filtering**, not private ingress, an Azure firewall, MCP protection
or a management-plane restriction. It does not govern direct backend calls or
registered MCP tool servers. For one list that also covers MCP tool servers,
see the [gateway-wide IP allow list](#gateway-wide-ip-allow-list).

### Gateway-wide IP allow list

`gateway_allowed_client_cidrs` adds one `ipFilter` policy, `action = "Allow"`,
to the `properties.policies` of the gateway's `default` workspace, which the
portal calls **Gateway** scope. According to the Azure/aigateway
[gateway baselines lab](https://github.com/Azure/aigateway/tree/fcac8910384749de906e665c8b9ff8dea74c9f16/labs/09-gateway-baselines),
a Gateway scope policy applies to every compatible model, alias and MCP tool
server, including ones registered later. The lab also states that a request
is blocked if any applicable policy blocks it, so a per-model
`model_allowed_client_cidrs` list can only narrow the gateway-wide one. This
layering is not tested here.

A PATCH replaces the whole workspace policy array, so
[gateway-policies.tf](../../gateway-policies.tf) reads the current policies,
keeps every entry except an existing `ipFilter` (matched case-insensitively,
including one added outside Terraform), appends the configured filter and sends
one PATCH.

| Value | Effect |
| --- | --- |
| `null` (default) | No read and no change; workspace policies stay unmanaged |
| `[]` | Removes the `ipFilter` and keeps the other workspace policies |
| CIDR list | One `Allow` `ipFilter`; ranges are deduplicated and sorted |

To remove the filter, apply `[]` first and then unset the input. Changing a
list directly to `null` only removes the Terraform action and sends no request,
so the filter stays on the gateway.

Entries must be valid IPv4/IPv6 CIDRs with a nonzero prefix; use `/32` or
`/128` for single addresses. IPv4 parts and prefix lengths must not have
leading zeros: `010.0.0.1/32` is rejected because other parsers can read it
as octal. IPv6 hextets such as `2001:0db8::/32` remain valid. Only the
standalone 2026 entry accepts this input.

> [!CAUTION]
> Every runtime caller outside the list receives `403`, including teammates,
> CI pipelines, hosted agents, the private lab's verification client and
> callers on another network, VPN or proxy. Use the egress address that the
> gateway observes. Behind a split-tunnel VPN, proxy or secure-access client,
> traffic to Azure can leave through a different egress than the one an
> IP-echo website reports, so listing the echoed address can still return
> `403 Forbidden`. Run the [bounded probe](#bounded-runtime-probe) and other
> runtime checks from an allowed address. Portal, CLI and ARM management are
> not affected. The lab notes that policy changes take up to a minute.

- **No drift detection.** A change made outside Terraform does not appear in a
  plan. To re-send the configured list, create and review a saved plan with
  `-replace` on `module.gateway.azapi_resource_action.gateway_ip_filter["default"]`
  (quoted for your shell), then apply it. The configuration checker reports a
  difference.
- **Fresh deployment:** the workspace ID is unknown at plan time, so the read
  happens during apply and the saved plan shows the request body as unknown.
- **Existing gateway:** the policies are read at plan time and the saved plan
  applies that snapshot, so avoid other workspace policy changes between plan
  and apply.
- Other workspace policies are kept but neither managed nor checked.
- `model_allowed_client_cidrs` remains a separate per-model policy.

### What clients see at a limit or fallback

The service documents these responses in the
[policy catalogue](https://ai.gateway.azure.com/docs/policies) and the
[cost-limit guide](https://ai.gateway.azure.com/docs/finops#cost-limits):

| Limit | Response | Client handling |
| --- | --- | --- |
| Token or request limit | `429` with `Retry-After` | Wait for the indicated time, then retry. |
| Monthly cost limit | `403` with `LlmCostQuotaExceeded` | Do not retry like a `429`; the allowance renews at the start of the next UTC month. |

An IP filter also returns `403`, so check the error before treating a `403` as
a cost-limit rejection. The cost limit checks the recorded spend before it
admits a call and adds the call's estimated cost afterwards, without reserving
a maximum. An admitted call can therefore cross the allowance, and concurrent
calls can briefly overshoot it. The amounts are gateway estimates, not billing
records; see [set cost limits](https://ai.gateway.azure.com/docs/finops/set-cost-limits).

For an alias, the gateway selects the available backend group with the lowest
priority number, then applies weights within that group
([priorities and weights](https://ai.gateway.azure.com/docs/models/priorities-and-weights)).
In the `gpt-latest` alias, each priority has one backend. The documentation
does not define when a backend counts as unavailable. This fallback comes from
the alias priorities, not from a separate `fallback` policy.

The following behavior is **not described in the public documentation** and
can change. Base client logic on the documented status codes and
`Retry-After`, and treat these details as informational:

- A gateway-limit `429` has `Retry-After` but no `x-ratelimit-*` headers. A
  `429` from the model provider also carries `x-ratelimit-*` and
  `retry-after-ms` headers, which distinguishes it from a gateway limit.
- The cost-limit `403` has no standard `Retry-After` header;
  `x-cost-per-month-retry-after` gives the seconds until the next UTC month.
  When a monthly cost limit applies, successful calls carry
  `x-cost-per-month-consumed`, the estimated cost of that call rather than a
  monthly total. `x-cost-per-month-remaining` appears once the allowance is
  used up.
- Calls rejected by a gateway limit are not forwarded to the model.
- Token and request limits can also admit slightly more than the configured
  value before they reject calls. Set each limit a little below the intended
  maximum.
- Successful responses carry `x-ms-served-model` with the model name and
  version that answered, so a client can see when a later backend served an
  alias call.
- The `gpt-latest` alias moves calls to the next backend after the model
  provider throttles the current one. The throttled call still returns the
  provider's `429`; the gateway does not retry it on the next backend, so
  clients need their own retry handling.
- When the priority-0 backend reaches its request limit, alias calls receive a
  gateway `429` and do not move to the next backend.
- After the provider throttling ends, calls return to the priority-0 backend
  after a short time. No documented setting controls when calls move to
  another backend or return.

### Backend safety, not gateway content safety

The [standalone contract](https://learn.microsoft.com/azure/ai-gateway/ai-gateway-resource#limitations)
does not support gateway `contentSafety`. Non-null `content_safety_severity`
inputs are rejected explicitly in the entry and shared implementation. Legacy
gateway behavior is unchanged.

Instead, `foundry-models.tf` explicitly binds every standalone deployment to
the existing system-managed `Microsoft.DefaultV2` policy using the
[deployment `raiPolicyName` property](https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2025-04-01-preview/accounts/deployments).
Terraform does not recreate or overwrite that policy, remove its additional
controls, or grant policy-management permissions. The binding is explicit even
when the service already selected that default.

The configuration checker reads that exact policy under the approved model
account and requires:

- `Blocking` mode and all eight enabled, blocking **Medium** core-harm filters:
  Hate, Selfharm, Sexual and Violence for both Prompt and Completion.
- Enabled jailbreak prompt blocking, protected-text completion blocking and
  protected-code completion annotation, matching this sample's DefaultV2
  text-model safety baseline.
- A matching `Microsoft.DefaultV2` binding on every deployment. Filter order is
  irrelevant; missing, duplicate or changed required controls fail the check.

See the [Foundry default-safety documentation](https://learn.microsoft.com/azure/foundry/guardrails/default-safety-policies).
The policy remains system-managed, so its effective configuration must be read
back rather than inferred from its name. Other built-in controls are retained;
the checker does not claim to verify every additional feature. Confirm support
and suitability for any custom model. This protects the configured model
prompt/completion path, **not all gateway traffic or MCP tool executions**
through registered tool servers.
Configuration checks are not proof of equivalent protection or a safety
certification; representative workload evaluation needs separate approval.

### MCP tool protection: separate extension

The optional `mcp_tool_servers` input registers existing remote MCP servers as
gateway tool servers: `type = "mcp"` with one `streamableHttp` endpoint whose
namespace is the map key. Each registration carries one `requestRateLimit`
policy with `counterKey = ["identity"]`, by default 20 calls per 60 seconds; the
caller-identity caveats above apply. Apart from the optional
[gateway-wide IP allow list](#gateway-wide-ip-allow-list), that is the only
tool-server control here. Model token/cost/request policies, the per-model IP
allow list and backend safety do not apply to tool servers. Registration does
not prove that the gateway can reach or route to a server, or that the rate
limit is enforced.

The portal also exposes `toolThreatProtection` for MCP tools with pre/post
invocation controls, associated with Agent 365, Defender and Purview. This
sample does **not** implement it, tool allow-lists or blocking, or credentials
for the remote MCP server. The default Microsoft Learn server needs none: its
[overview](https://learn.microsoft.com/training/support/mcp) states that no
authentication is required and that use is subject to the Microsoft Learn
Terms of Use.
`subscriptionRequired` is not sent, and its service default is unverified.
A future protection extension needs backend authentication where required, the
applicable protection service prerequisites and access, and a separately
approved test scope. Do not attach it to models or claim gateway-wide coverage.
CORS and extra fallback policy types are not asserted as verified standalone
creation options here.

## Deployment gates

Review the explicit backend-safety design and its model-only scope before
approving a saved plan. The updated profile no longer sends unsupported gateway
content-safety settings, but this does not establish live API acceptance or
runtime protection. The configuration checker must pass before the bounded
probe obtains credentials or sends inference. Enforcement, filter behavior
and failover require separate, approved live checks.

Also resolve any Azure Policy or service-readback differences before approving
a saved plan. Do not use ignored changes, targeting, policy exemptions or
wider connection sharing to hide a mismatch.

If `gateway_allowed_client_cidrs` is set, confirm the egress address that the
gateway sees for every runtime caller, including CI pipelines and hosted
agents, before approving the saved plan; callers outside the list receive
`403`.

## API contracts and lifecycle

| Resource family | Version used by this entry |
| --- | --- |
| Standalone gateway; model provider/catalog/aliases; runtime key | `2026-09-01-preview` |
| Telemetry exporter | `2025-09-01-preview`, separately pinned pending live acceptance |
| Gateway MCP tool servers (`toolServers` under the `default` workspace) | `2025-09-01-preview`, separately pinned; acceptance unverified |
| Gateway-wide policies (`properties.policies` of the `default` workspace, read then PATCHed) | `2025-09-01-preview`, pinned as `gateway_policy_api_version` in [../../main.tf](../../main.tf); used only when `gateway_allowed_client_cidrs` is not `null`; acceptance unverified |
| Foundry model deployments and the read-only system RAI-policy check | `2025-04-01-preview`; not changed to the gateway API date |
| Project AppInsights connection | `2025-06-01`; project-local, not an account connection |

The dedicated model-serving account sets `allowProjectManagement = true` for
API2026; the legacy contract retains `false`. This capability neither creates
a project on the models account nor grants permissions. The existing agent
project remains on the separate agents account. The
[Foundry project guidance](https://learn.microsoft.com/en-us/azure/foundry/how-to/create-projects)
states that the capability cannot be changed after resource creation. For an
existing API2026 account, confirm its live value is already true before applying.
Do not treat a capability downgrade as network hardening, or infer why a
historical requested value and live value differed.

The root follows the [standalone-resource contract](https://learn.microsoft.com/azure/ai-gateway/ai-gateway-resource)
and [published creation schema](https://learn.microsoft.com/azure/templates/microsoft.apimanagement/2026-09-01-preview/aigateways).
That schema makes `sku` optional. This sample omits it rather than assuming
`Consumption` or substituting an API Management Premium tier. Without a
backend subnet the gateway body is `properties = {}`. The Premium **container
registry** is a separate resource, not a gateway SKU.

The telemetry pin is independent: a newer exporter contract has not been
established here, so do not mechanically change every API date. Preview schema
validation is disabled; neither that setting nor successful offline tests
proves that Azure accepts every request. Verify the `gateway_api_versions`
output, whose six keys include `tool_servers` (`null` for the legacy contract),
and each exact saved-plan payload before approved live acceptance. The
gateway-wide policy version is not in that output; check it in the saved-plan
`gateway_ip_filter` action.

Tool servers follow the same precedent. The public `2026-09-01-preview`
specification describes only the root gateway resource, and the blue-octopus
reference sample (see [Provenance](#provenance)) registers tool servers with
`2025-09-01-preview`. The body sends `displayName`, as that sample does, while
the GA `2026-11-01` specification names the property `name`. Which property the preview version expects, and whether ARM
accepts this child type and version in every supported region, are unverified.

- Gateway `prevent_destroy` remains enabled.
- Backend networking is creation-time configuration; changing it triggers
  replacement, which deletion protection can block. Do not bypass that guard.
- Alias property changes retain replacement behavior, with create
  `If-None-Match: *` and delete `If-Match: *` precondition headers. These are not
  proof of optimistic concurrency against another writer. Review the saved plan
  for alias recreation and impact.
- Tool servers use the same headers, and any property change destroys and
  recreates the tool server, which is briefly unavailable meanwhile. The GA
  `2026-11-01` specification requires `If-Match` for PATCH, DELETE and PUT
  updates, and the sample does not track ETags. Review the saved plan for
  tool-server recreation.
- For the 2026 contract, a gateway postcondition requires Azure to return a
  non-empty `frontend.defaultHostname`. Otherwise Terraform stops with "The
  2026 gateway is not ready", creates no dependent child resources in that
  apply, and later plans also fail until Azure returns the hostname. A missing
  hostname is now an error rather than an empty `gateway_endpoint` output. Wait
  for provisioning, then create, review and apply a fresh saved plan. The
  legacy gateway is unchanged.
- The postcondition deliberately does not require `provisioningState =
  "Succeeded"`. Right after an in-place gateway update, Azure can return
  `Updating` together with the hostname; in live testing, a `Succeeded` gate
  stopped such an apply before its dependent resources were created. The check
  reads only the hostname the gateway already exported, so it adds no gateway
  update to existing deployments' plans. The
  [configuration checker](#monitoring-and-acceptance) still requires
  `Succeeded` when it reads the gateway after apply.
- Provider placement, resource/data labels, instance keys and the legacy
  connector `moved` block are unchanged. Moving blocks among `.tf` files in the
  same module is not a state migration.

## Network and access boundaries

The baseline is **public endpoints with authentication**, not unauthenticated
access and not private-only access. Gateway private ingress, its DNS path and a
public-access-disable switch are not implemented by this entry. The optional
[gateway-wide IP allow list](#gateway-wide-ip-allow-list) narrows which public
caller addresses the gateway serves at runtime; it does not make the gateway
private.

An optional external `gateway_backend_subnet_id`:

- References an existing subnet delegated to `Microsoft.App/environments`.
- Requires the VNet region to match the gateway region.
- Configures creation-time **outbound backend integration**, not client ingress.
- Does not create a VNet, subnet, NSG, route, resolver, private endpoint or DNS.

Private-ingress availability must be discovered and verified for the actual
standalone gateway and subscription. This entry does not implement gateway
private endpoints or public-disable enforcement; its outbound input does not
port the legacy private scenarios.

The separate owned-lab opt-in can create a backend foundation, as described
below; it does not change the gateway ingress boundary.

Do not copy the legacy private-hosted-agent, test-VM or public-network flags into
this entry. Separate approval and implementation would be needed for private
ingress or a new networking feature.

### Backend-private connectivity

`standalone_backend_public_network_access = "Disabled"` requests disabled
public access on the model and agent accounts, Storage and registry, and both
public ingestion and query access on the two Insights components and two
workspaces. `null` preserves baseline and legacy behavior. This is a
**backend-only setting**, not gateway public-access enforcement.

The access setting **does not itself create** endpoints, DNS, an Azure Monitor
Private Link Scope (AMPLS), a private client or agent egress. Choose the
applicable foundation explicitly:

| Foundation | Contract |
| --- | --- |
| External | Supply `gateway_backend_subnet_id` and separately provision/verify backend private endpoints, DNS, monitoring private access and a private caller; this input only integrates outbound gateway traffic |
| Owned lab | Enable `api2026_private_lab_enabled` with fresh single-group inputs, matching regions, a fresh SSH public key and explicit backend `Disabled`; do not supply an external subnet |

The owned lab in [api2026-private-network.tf](../../api2026-private-network.tf)
creates an unpeered VNet, delegated gateway-outbound subnet, private-endpoint
subnet with disabled endpoint network policies, and verification-client subnet.
It adds client/gateway NSGs, client NAT/public egress IP, private endpoints for
Blob, models, agents, registry and AMPLS, private DNS zones/links/zone groups,
and private-only AMPLS ingestion/query with both workspaces and components
linked. These are backend endpoints, **not a gateway private endpoint**.

[api2026-private-client.tf](../../api2026-private-client.tf) adds a private-addressed
verification VM/NIC without public SSH ingress, two distinct user-assigned test
identities, positive-test scoped grants, an export-restricted OS disk, a
private Blob test container and a `StorageRead` diagnostic to the gateway
workspace. The source does not grant the negative test identity access.
The client is not a hosted agent; source configuration does not prove its
network or authorization behavior.

**Storage rules depend on the selected foundation.** In the external-foundation
mode, the existing `AzureServices` bypass is retained. Disabled mode also sets
`networkAcls.defaultAction = "Deny"`. Conditional AzAPI `ignore_body_changes`
preserves only the live `properties.networkAcls.resourceAccessRules` list on
updates, so externally managed scanner rules are not cleared or adopted.
The empty list in the body is the overlay placeholder: AzAPI reads and
substitutes the existing list before updating an existing account. On creation,
there is no existing list to preserve. This is not permission to ignore general
drift; public access and firewall default remain managed and checked. Verify
the list before and after a later approved apply.

The **fresh owned lab** instead sets Storage bypass to `None` and does not
enable that external-rule preservation overlay. See the conditional body and
`ignore_body_changes` in [foundry-agents.tf](../../foundry-agents.tf); do not apply
the external-foundation exception to all modes.

Disabled controls and `Deny` are not proof of repaired public routes,
exception-free access or private connectivity. Verify each producer, reader
and public-negative path separately. Neither foundation implements gateway
private ingress, agent egress or parity with legacy scenarios 01/02.

## State and lifecycle

Use a new state for this entry. `module.gateway` is a different address boundary
from the parent root; neither copying a state file nor changing a working
directory adopts a legacy workload safely. No import, migration or
resource-address rewrite is included.

With `api2026_existing_resource_group = true`, Terraform reads the group named
by `api2026_resource_group_name` through a
`Microsoft.Resources/resourceGroups@2021-04-01` data lookup; the plan fails if
the group does not exist. All sample resources go into that one group.
Terraform never creates or deletes the reused group: `terraform destroy`
removes only the sample-managed resources inside it. This is not import or
adoption, so resources already in the group stay unmanaged. Choose the setting
before the first apply, with fresh state, and **never toggle it on an existing
state**: `false` to `true` plans to destroy the Terraform-owned group, and
deleting a resource group in Azure deletes every resource in it; `true` to
`false` tries to create a group that already exists. Stop if a plan shows a resource-group destroy.

For local state, protect the entry directory's state, backup and `.terraform`
metadata. For a separately configured remote backend, use the approved distinct
key/workspace and access controls. Never share another workload's backend
identity or `TF_DATA_DIR` just because the checkout path differs.

State and saved plans can contain connection strings and other sensitive
material. Store them privately, avoid raw state/plan JSON in reports or commits,
and keep all operational inputs together for repeat plans. Use an explicitly
reviewed saved plan for changes; retain or remove resources only with approval.

## Outputs

All outputs are described in [outputs.tf](../outputs.tf).

| Outputs | Purpose |
| --- | --- |
| `resource_groups` | Actual group names keyed by three logical workloads; names coincide in fresh single-group mode and report the reused group's name in existing-group mode |
| `gateway_id`, `foundry_models_id`, `model_deployment_ids` | Gateway, model account and deployment ARM IDs |
| `gateway_endpoint`, `project_endpoint` | Service endpoints, not connectivity proofs |
| `project_id` | Project ARM identifier; no running-agent claim |
| `gateway_api_key_id` | Runtime key resource ID only, never the key value |
| `gateway_contract`, `gateway_api_versions` | Contract with its `existing_resource_group` flag, optional outbound-subnet metadata and exact API versions, including `tool_servers` |
| `backend_public_network_access` | Requested PaaS/monitoring settings, not actual enforcement or private-connectivity proof |
| `model_api_configuration`, `model_alias_configuration` | Model API formats/endpoints, callable aliases and backend order |
| `mcp_tool_server_ids` | Registered MCP tool-server ARM IDs keyed by name; `{}` when none; not reachability evidence |
| `application_insights_ids`, `gateway_monitoring` | Monitoring destinations/exporter metadata, not telemetry-delivery evidence |
| `container_registry_endpoint`, `storage_account_name` | Agent-support dependency addresses |
| `api2026_private_lab` | Owned-lab inventory and public identity metadata; `null` outside lab mode; not private-path or runtime evidence |

## Monitoring and acceptance

The entry configures an `ApplicationInsights` exporter (output metadata
`applicationInsights`) with the intentionally retained exporter API.
The current [observability documentation](https://ai.gateway.azure.com/docs/observability)
describes **metrics, logs and traces as independently enabled OTLP signals**,
including token metrics. Application Insights portal monitoring covers token
usage, requests, MCP executions, traces and policies.

These are service capabilities, not proof that every signal is enabled or
delivered by this configuration. The sample can register MCP tool servers, but
delivery of MCP execution logs is not tested. The documentation supplies no KQL
table or field schema: verify actual delivered data and its correlation fields
rather than inventing queries or treating exporter configuration as delivery
evidence.
Do not carry over the legacy [OTLP procedure](../../docs/monitoring.md) or its
schema assumptions to this entry.

[Test-Api2026Deployment.ps1](../../scripts/Test-Api2026Deployment.ps1) is a
**configuration-only** checker. Its required inputs are `-TerraformDirectory`,
`-SubscriptionId`, `-TenantId` and `-AllowedResourceGroups` (the exact three
distinct approved names by default, or one with `-SingleResourceGroup`).
Optional `-ReportPath` must be a new file in an existing
directory. It uses the explicitly selected Azure account/subscription without
changing that account selection.

It reads selected outputs and `terraform show -json` in memory, validates
isolated module addresses, allowlisted IDs/groups and API versions (exactly six
`gateway_api_versions` keys, including `tool_servers`) before ARM reads, and
returns a sanitized SchemaVersion 2 report. A failure throws/returns
nonzero without raw state or Azure bodies. Source-derived configuration/policy
expectations are not runtime observations. It also reads the fixed
`Microsoft.DefaultV2` system policy within the validated models account; this
policy is not counted as a Terraform-managed resource.

After foundational scope/resource checks pass, independent model, safety,
connection, role, exporter and `tool-servers` checks all run, plus
`gateway-policies` when the gateway IP filter is managed. A
connection-sharing mismatch is retained as a failure even if unrelated checks
pass: the report and command remain failed, and the bounded probe stops before
credentials or inference.

Before ARM reads, the checker validates each `mcp_tool_server_ids` entry in
state: its name, its ARM ID under the gateway's `default` workspace, the
tool-server type and API version, `type = mcp`, the single endpoint (namespace
equal to the key, kind `mcp`, transport `streamableHttp`, credential-free
`https://` URL) and the identity-keyed `requestRateLimit` policy. The
`tool-servers` check then compares each live ARM read-back with the state body.
It never calls the MCP server, so the report's `toolServerReachability` entry is
always `NOT TESTED`. No read-back projection exists for tool servers yet: if
ARM does not echo a configured property such as `displayName`, the check fails
and the difference must be investigated, not hidden.

When `gateway_allowed_client_cidrs` is not `null`, the checker also validates
the `gateway_ip_filter` action in state before ARM reads: its type and API
version, the `default` workspace ID, a body that replaces only
`properties.policies`, and at most one duplicate-free, non-empty `Allow` filter
of valid CIDRs. The `gateway-policies` check then reads the live workspace and
compares only the IP filter, canonically (host bits masked, IPv6 normalized,
duplicates and order ignored); a difference fails the check. Its evidence
reports the scope, mode (`Allow` or `Removed`), range count and API version but
never the ranges, and records `enforcement = NOT TESTED`.

### Advanced checker options

These are modifiers to the [main verification command](../README.md), not another
deployment sequence. The bounded probe forwards them to the same checker.

| Option | Scope and requirement |
| --- | --- |
| `-SingleResourceGroup` | Require the supported fresh single-group layout and exactly one approved group name; it does not consolidate or adopt resources |
| `-ExistingResourceGroup` | Requires `-SingleResourceGroup`; not supported with `-PrivateLab`. Require `gateway_contract.existing_resource_group = true` and no Terraform-managed resource group in state; a mismatch either way fails |
| `-PrivateLab` | Verify the owned lab inventory; requires `-SingleResourceGroup` and `-ExpectedBackendPublicNetworkAccess Disabled` |
| `-ExpectedBackendSubnetId "<exact-subnet-ARM-id>"` | Admit only the explicitly approved same-subscription external subnet reference outside workload groups; does not broaden the managed-resource group allowlist |
| `-ExpectedBackendPublicNetworkAccess Disabled` | Require matching outputs, state and live backend/monitoring settings; does not infer actual routes, DNS, private traffic or public-path denial |
| `-ExpectedPrivateEndpointSubnetNsgId "<exact-NSG-ARM-id>"` | Read-only, tightly scoped external NSG exception for the owned lab; see [constraints](#external-private-endpoint-nsg) |
| `-ReportPath` | New report file in an existing private directory; never overwrite existing evidence |

### Live readback projections

The checker records narrowly accepted **live-only** service projections in
`readbackProjections`; the configured Terraform contract remains required.

| Live projection | Exact acceptance boundary |
| --- | --- |
| Catalog omits `apiFormat` | Only for configured `OpenAIChatCompletions` with live `providerKind = Foundry`; deployment, endpoints and ordered policies remain checked |
| Exporter omits `kind` | Does not replace or relax the configured `ApplicationInsights` requirement; destination and payload capture remain checked |
| Owned Blob diagnostic explicitly returns null `logAnalyticsDestinationType` | Only for configured `Dedicated`, with the exact workspace and configured log/metric categories and settings still checked |

A missing diagnostic destination field is not an explicit null; missing
required fields and explicit wrong values still fail. These comparisons do
not prove telemetry delivery, a resource-specific destination table or policy
enforcement, and are not blanket drift suppression.

### Policy-modified storage access

An inherited Azure Policy with a Modify effect can rewrite the agent storage
account to `publicNetworkAccess = Disabled` whenever Terraform writes
`Enabled`. Live testing in a subscription where a management-group assignment
applies such a policy showed:

- Every later plan shows the storage account as an in-place update
  (`publicNetworkAccess = "Disabled" -> "Enabled"`) and can also list the
  storage connection, whose target is recomputed. Applying the plan does not
  clear the drift, because the policy modifies that write as well.
- The checker fails with `Configured value mismatch: storage
  properties.publicNetworkAccess`, so the bounded probe stops before
  credentials or inference.
- Direct gateway model and MCP calls, made outside the bounded probe, still
  succeeded. Agent behavior with storage public access disabled was not tested.

Do not hide the drift with `ignore_changes` or a new readback projection.
Request a policy exemption for the workload resource groups, or record the
failure as a known finding for that environment.

### External private-endpoint NSG

Private-lab verification **strictly rejects an NSG on its private-endpoint
subnet by default**. With separate explicit approval, supply
`-ExpectedPrivateEndpointSubnetNsgId` for the exact external NSG. The checker
requires all of the following:

- Same subscription and managed group, expected region, and exact live
  attachment to the private-endpoint subnet.
- Private-endpoint network policies remain `Disabled`.
- That subnet is the NSG's sole subnet attachment; no NIC or other subnet
  attachment is allowed.
- Zero custom rules and all six canonical default rules, including their
  expected selectors, directions, priorities and actions; extended selectors
  are rejected.
- The NSG is not Terraform-managed in the inspected state.

This option performs scoped reads only: no import, modification or adoption.
Unknown origin is not assumed to be Azure Policy. Other network restrictions
remain unchanged. The bounded model probe forwards the option.

### Project monitoring connection

API2026 creates only `project_insights_connection["agents"]` beneath the
existing project, using `2025-06-01`, the existing Insights component/connection
string and explicit `isSharedToAll = false`. Both `target` and
`metadata.ResourceId` use the **full component ARM ID**, following the
category-specific Azure-Samples
[existing-project example](https://github.com/Azure-Samples/bring-your-own-agent-to-m365-accelerator/blob/6f50dae5eac454897c1e2ebbb3b018ecda500341/infra/modules/foundry/ms-foundry-appinsights-connection.bicep).
It creates no account-level AppInsights connection. The legacy contract keeps
its shared account connection and name-form metadata, with a Terraform `moved`
block retaining identity after conditional indexing.

The checker requires the exact project connection and unshared settings for
both project AppInsights and Registry. Project 404, wrong target/metadata or
normalized sharing=true remains a failure. It reports returned `isDefault`
without setting it or claiming default selection. `sharedUserList` is not a
project-binding mechanism. Plan/schema success does not prove false-sharing
persistence, repeat-PUT durability, stored-credential authentication,
cross-project isolation or agent telemetry.

An account connection may be shared/inherited by projects, making a project
child path appear to exist before a project-local connection is created.
If an earlier API2026 deployment has this redundant account connection,
recovery requires **separately approved account-only removal**: review and
apply that removal plan, verify the inherited project view is absent, then
generate an ordinary fresh plan for project-local creation. Do not import
the inherited projection as a second owner or run creation concurrently with
removal. Targeted actions are incomplete; any full continuation requires its
own fresh plan and validation. Do not claim concurrent or targeted completeness.

If component changes make `ConnectionString` unknown, inspect the **whole
action graph**, including exporter and connection actions; do not infer a
stored secret or working agent telemetry from an unknown value.

### Acceptance gates

| Gate | Meaning of the available evidence |
| --- | --- |
| Offline validation | Canonical [Test-Offline.ps1](../../scripts/Test-Offline.ps1); local and mocked checks only |
| Configuration | `configurationStatus` is `PASS` or `FAIL`; a configuration pass still has `overallStatus = INCOMPLETE` |
| Runtime inference and caller authentication | Separate approved, bounded live evidence required; not established by this checker |
| Token/cost/request/IP enforcement and failover | Separate controlled behavior checks; emitted policy/routing JSON is insufficient; the `gateway-policies` check reports gateway-wide IP enforcement as `NOT TESTED` |
| Tool-server reachability and rate limit | `toolServerReachability` is `NOT TESTED`; registration and ARM read-back prove neither gateway routing to the MCP server nor rate-limit enforcement |
| Backend safety configuration | Verify every deployment binding, effective blocking mode, eight Medium harm filters and the required text-model controls; reports enforcement as `NOT TESTED` |
| Safety behavior | Separate representative workload evaluation; no unsupported gateway `contentSafety` or MCP-coverage claim |
| Telemetry delivery | Verify the enabled signals arrive in the intended Insights/Log Analytics destination, using observed data/schema and verified request correlation rather than configuration alone |
| Repeat-plan idempotence and portal review | Separately review the retained workload with its complete approved inputs/state |
| Agent runtime | Requires a separately built/deployed agent and its own evidence |
| Private ingress | **NOT IMPLEMENTED** by this entry |

The checker's runtime, telemetry delivery, failover/policy, tool-server
reachability, idempotence, portal and agent-runtime gates remain `NOT TESTED`.
The offline [acceptance fixtures](../../tests/Test-Api2026Acceptance.ps1) mock
Terraform, Azure and HTTP; their results are not live acceptance.

### Bounded runtime probe

After configuration approval, [Test-ModelAliases.ps1](../../scripts/Test-ModelAliases.ps1)
offers an opt-in bounded mode. From this entry's directory, with approved
runtime-call scope and the already-selected Azure account:

```powershell
$runId = [guid]::NewGuid().ToString()
& ..\scripts\Test-ModelAliases.ps1 `
  -Bounded `
  -TerraformDirectory (Get-Location).Path `
  -SubscriptionId "<approved-subscription-guid>" `
  -TenantId "<approved-tenant-guid>" `
  -AllowedResourceGroups @("<gateway-group>", "<models-group>", "<agents-group>") `
  -Authentication ApiKey `
  -MaxOutputTokens 64 `
  -TimeoutSeconds 13 `
  -RunId $runId
```

For a single-group or owned-lab layout, use the same approved
[layout and backend checker options](#advanced-checker-options) on this probe
as on the configuration check; changing only the group list is insufficient.

If `gateway_allowed_client_cidrs` is set, run the probe from an address in that
list; calls from other addresses receive `403`.

`-MaxOutputTokens` and `-TimeoutSeconds` are explicitly required in bounded
mode. The request uses `max_completion_tokens`; the probe does not redirect or
retry. These bounds are not a zero-cost guarantee or a hard wall-clock deadline:
DNS resolution can exceed a short nominal timeout. Read the report's
`timeoutScope` for the actual timeout behavior. Bounded mode first runs the
configuration checker, binds calls to the ARM-returned gateway origin and uses
the explicit subscription for key/token acquisition.

- Use `-Authentication EntraId` instead for a separately approved Entra caller
  with the required data-plane access and the
  [gateway audience](#caller-authentication). A successful key call does not prove
  Entra authorization.
- Optional `-TestNegativeAuthentication` sends missing and synthetic-invalid
  credentials to the first alias. It accepts only 401 or an auth-classified 403;
  it does **not** test a valid-but-ungranted identity.
- `-RunId` is optional; the explicit GUID above helps identify this approved run.
  Run/trace IDs are client evidence, not proof that delivered telemetry exposes
  a matching correlation field.
- Optional `-ReportPath` atomically creates a new private report file in an
  existing directory and preserves existing evidence. Structured reports exclude
  raw model text, credentials, connection strings and state; do not capture raw
  secrets through other commands.

The runtime report keeps `overallStatus = INCOMPLETE`; `status = PASS` covers only
the bounded chat and selected authentication checks. It does not test the
Responses API, MCP tool servers or complete policy/failover, telemetry-delivery,
idempotence, portal, agent-runtime or private-ingress gates. Unbounded/default
script behavior remains available for existing legacy consumers; it is not the
path described here.

## Provenance

The model/version pins, capacities and routing originate from the public [historical Bicep snapshot](https://github.com/annawiewer/ai-gateway_test/blob/714419fd6eba38a067f325b1b8978adc7d5cbc6c/samples/bicep/README.md)
captured on October 29, 2026, including changes that were unmerged at that time.
Governance settings are now maintained for this standalone entry, as documented
above. This is origin attribution, not a current PR-status or live-acceptance claim.

The default Microsoft Learn MCP tool server and existing resource-group reuse
were adapted from ideas in Damien Aicheh's blue-octopus repository, folder
[`catalog/ai-gateway/standalone` at commit `3222da9`](https://github.com/damienaicheh/blue-octopus/tree/3222da9a84ade7d4bb18f6e5b0e402ef6c7a893d/catalog/ai-gateway/standalone),
and the 2026 gateway readiness check was inspired by the postconditions on its
data sources. They were re-implemented for this sample rather than copied; the
tool-server body follows the payload shape used there.

The gateway-wide IP allow list follows the read, merge and PATCH pattern of the
Azure/aigateway lab
[`labs/09-gateway-baselines` at commit `fcac891`](https://github.com/Azure/aigateway/tree/fcac8910384749de906e665c8b9ff8dea74c9f16/labs/09-gateway-baselines),
re-implemented in Terraform. Unlike the lab, this merge drops an existing
`ipFilter` case-insensitively.
