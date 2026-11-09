# Standalone AI Gateway architecture

[Deployment guide](../README.md) · [Configuration reference](reference.md) · [Terraform overview](../../README.md)

This page explains the infrastructure in this Terraform entry. It describes
source configuration, not a deployed inventory or evidence of acceptance.
The baseline uses **authenticated public gateway ingress**. The optional private
backend foundation does not add gateway private ingress or port the legacy
private scenarios.

## What is deployed

The entry calls the shared implementation as `module.gateway` with the standalone
`2026` contract. The three logical workloads are:

| Workload | Configured resources | Source |
| --- | --- | --- |
| Gateway | Standalone gateway, Foundry provider, catalog models and policies, aliases, default runtime key, optional MCP tool servers (the entry default registers Microsoft Learn), gateway monitoring and exporter | [Gateway](../../ai-gateway.tf), [routing](../../model-routing.tf), [tool servers](../../mcp-tool-servers.tf), [monitoring](../../monitoring.tf) |
| Models | Dedicated Foundry model-serving account and selected model deployments, explicitly bound to system-managed `Microsoft.DefaultV2` safety | [Foundry models](../../foundry-models.tf) |
| Agents | Separate Foundry account and project, Storage, Premium container registry, project connections, scoped roles and separate monitoring | [Agent support](../../foundry-agents.tf), [roles](../../rbac.tf), [monitoring](../../monitoring.tf) |

By default these workloads use **three managed resource groups**. For fresh
state, `api2026_resource_group_name` selects one exact managed group shared by
all three workloads. Adding `api2026_existing_resource_group = true` instead
reuses an existing group of that name, which Terraform reads but never creates
or deletes. The logical workload keys remain distinct even when their group
names coincide. These options are not switches for consolidating or adopting an
existing deployment; never toggle the reuse flag on an existing state. Names,
group selection and API selection live in [the shared main.tf](../../main.tf).

The gateway omits an explicit SKU; **Premium refers to the registry**, not an
API Management gateway tier. No legacy connector gateway or agent application
is deployed by this entry. Creating a project, registry and connections does
not build an image, host an agent or prove an agent runtime.

## Request path and identity boundaries

```text
Caller
  -- approved gateway key OR authorized Entra bearer token -->
Authenticated public standalone gateway
  -- alias selects catalog model; model-call policies apply -->
Foundry provider
  -- gateway managed identity + model-account role -->
Selected deployment on the dedicated models account
  -- configured Microsoft.DefaultV2 backend safety -->
Model response through the gateway
```

These are separate authorization boundaries:

- **Caller → gateway:** the runtime key is gateway-wide; optional
  `gateway_access_principals` add Entra invocation access without disabling keys.
  Backend permissions do not authorize a caller. See
  [caller authentication](reference.md#caller-authentication).
- **Gateway → model account:** the gateway managed identity authenticates to
  Foundry. Alias backend keys must refer to deployments in the complete model
  map. The model account is distinct from the agents account.
- **Gateway → MCP tool server:** each registered tool server points the gateway
  at a remote MCP URL with a request rate limit keyed by caller identity. The
  sample configures no credentials for the remote server; the Microsoft Learn
  default needs none. Caller authentication, routing, rate limiting and
  reachability on this path are unverified. See
  [MCP tool protection](reference.md#mcp-tool-protection-separate-extension).
- **Project → agent dependencies:** the project's own managed identity receives
  scoped dependency roles. It is not the gateway identity. Optional developer
  grants are additional access, not required runtime identity.
- **Optional verification client:** the private lab adds separate test identities
  and scoped positive-test grants; these do not replace either service identity.

The models account has `allowProjectManagement = true` for this contract, but
there is no project on it. The agent project remains on the agents account.
This capability grants no additional permissions and is not a mutable network
hardening control; see [API lifecycle](reference.md#api-contracts-and-lifecycle).

## Telemetry is a separate flow

```text
Gateway telemetry exporter
  -- configured ApplicationInsights destination -->
Gateway Application Insights --> gateway Log Analytics workspace

Agent project AppInsights connection
  -- connection configuration for a separately deployed agent -->
Agent Application Insights --> agent Log Analytics workspace
```

The exporter uses its own API pin and disables payload capture. The project
connection uses the existing agent component's connection string, with
project-local, unshared scope. See
[project monitoring connection](reference.md#project-monitoring-connection).
Neither arrow is evidence of delivered signals, stored-credential
authentication, request correlation or agent telemetry. Monitoring delivery
and runtime behavior are [separate acceptance gates](reference.md#monitoring-and-acceptance).

The private lab additionally configures a Blob `StorageRead` diagnostic to the
gateway workspace. It does not establish that a resource-specific table
received records.

## How the Terraform files fit together

| Layer | Relationship |
| --- | --- |
| Entry root | [main.tf](../main.tf) calls `module.gateway` with `source = "../"` and fixes `gateway_contract = "2026"`; the entry directory has its own state boundary |
| Inputs | [variables.tf](../variables.tf) exposes the entry controls; [main.tf](../main.tf) forwards them to the shared module; [shared variables](../../variables.tf) enforce inherited validations |
| Model defaults | [model-profile.json](../model-profile.json) supplies each map when that input is null; custom `model_deployments` and `model_aliases` independently replace entire maps, not merge |
| Tool servers | [variables.tf](../variables.tf) defaults `mcp_tool_servers` to the public Microsoft Learn server; a supplied map, including `{}`, replaces it; [mcp-tool-servers.tf](../../mcp-tool-servers.tf) registers each entry under the gateway's `default` workspace |
| Unsupported inputs | [legacy-input-guards.tf](../legacy-input-guards.tf) rejects legacy flags rather than silently accepting private-ingress claims |
| Implementation | The entry's parent directory supplies the shared module, but remains a separate legacy root when selected directly; [file map](reference.md#file-map) identifies each responsibility |
| Outputs | [outputs.tf](../outputs.tf) forwards scoped IDs, endpoints and review metadata; endpoints are not connectivity proofs and no runtime key value is exposed |

Terraform loads **all `.tf` files in each module together** and derives a
dependency graph from references and explicit dependencies. Filenames are not
an execution order; moving blocks within the same module does not create a
new module or migrate state. A readiness postcondition on the 2026 gateway
stops the apply before dependent resources are created unless Azure returns a
frontend hostname.

Use the [deployment guide](../README.md) for the single plan/apply sequence and
[state reference](reference.md#state-and-lifecycle) for isolation requirements.
Neither copying legacy state nor reusing its backend is part of this design.

## Baseline versus backend-private options

| Mode | What the source supplies | What it does not establish |
| --- | --- | --- |
| Baseline | Authenticated public endpoints; three groups by default, or a fresh-state single group that is created or reused | Private-only access or live runtime/telemetry acceptance |
| External backend foundation | `gateway_backend_subnet_id` references an existing delegated outbound subnet; optional backend `Disabled` settings require separately owned private connectivity | The access setting does not create endpoints, DNS, AMPLS, a private client or agent egress |
| Owned private backend lab | Explicit single-group opt-in creates the outbound/private-endpoint/client subnets, backend endpoints and private DNS, AMPLS, NAT egress, verification VM, test identities and diagnostic resources | Gateway private ingress, a hosted agent, actual private traffic, public-negative results or telemetry delivery |

The lab requires `api2026_private_lab_enabled = true`, an exact
`api2026_resource_group_name`, matching workload/gateway regions, a fresh public
SSH key and explicit backend access `Disabled`; it rejects an external backend
subnet and a reused existing group. Its implementation is in
[network foundation](../../api2026-private-network.tf) and
[verification client](../../api2026-private-client.tf).

Storage hardening differs between the external-foundation and fresh owned-lab
modes, including bypass and externally managed rule preservation. Read the
[backend-private contract](reference.md#backend-private-connectivity) before
selecting a mode. Backend subnet integration is creation-time and
replacement-sensitive; it is not a public-to-private ingress conversion.
No resource-count, configuration-pass or operational-success claim applies
universally to these configurations.
