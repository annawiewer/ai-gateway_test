# Architecture: what each service does

This guide separates the **base Terraform sample**, the **verified private-agent
reference**, and the **optional Entra caller configuration**, without publishing
subscription-specific identifiers. For a model call, the application asks a
question, the gateway checks and routes the request, and the model generates
the answer. The gateway is neither the model host nor the agent runtime.

The private-network reference describes the `private-only` end-state profile **after
staged setup**. The two deployment paths are **Public** and **Private-only**;
`private-connectivity` is only an intermediate provisioning profile. The resource and preview
restrictions in the [README](../README.md) still apply; this guide does not
change the sample's resource type.

For the execution order, use the [step-by-step deployment guide](../deployment.md#start-here).
This guide explains connections, not instructions to recreate existing resources.

**Existing-network references:**
[Overall architecture](../README.md#existing-network-reference-architecture) |
[Network and DNS](../deployment.md#existing-network-connectivity-reference) |
[Resource ownership](../deployment.md#platform-handoff-before-a-plan) |
[Request sequence](#end-to-end-private-request-flow).

<a id="a-few-terms-before-reading-the-diagrams"></a>

### A few useful terms

| Term | Meaning in this sample |
| --- | --- |
| VNet / subnet | A virtual network and a subdivision of its address space. The gateway integration subnet and private-endpoint subnet have different jobs. |
| Private endpoint | A private network address connected to an Azure service. This sample creates new workload endpoints even when it reuses a VNet. |
| Private DNS zone | Name records that let clients find private endpoints. An existing central zone remains owned by the platform. |
| DNS resolver | The service that answers or forwards name lookups. Its resource ID is **not** a private DNS zone ID. |
| DNS zone group | The association between one private endpoint and selected DNS zones. Creating this association does not take ownership of the central zone. |
| Terraform state / backend | The record of managed resources / the place that record is stored. The gateway and central network do not become one owner just because they are connected. |
| Plan / apply | A proposed change / execution of a reviewed proposal. A plan alone has not created resources. |

## 1. Base sample architecture

This is the **Public** configuration. The following network section describes
**Private-only**; the agent section adds the optional private hosted-agent runtime.

```text
Application -> AI Gateway -> Foundry model
```

The response comes back along the same path. Telemetry is exported separately;
it is not part of the synchronous model response. Configured connections and
permissions are **not proof of data flowing**.

Hosted-agent execution is a separate activity: Terraform prepares its
infrastructure but does not build an image, deploy agent code or start a
container. A simple application or the gateway Playground can call a model
without running an agent.

### Runtime and application infrastructure

| Component | Why it is here | What it does not do |
| --- | --- | --- |
| **AI Gateway** | Provides one model API endpoint. It validates a runtime API key or Entra token and invocation role, resolves aliases such as `gpt-mini`, enforces a token budget per caller identity and forwards the request. | It does not execute the model or agent code. It is not Azure Application Gateway, and no Application Gateway is deployed here. |
| **Foundry model account and deployments** | Hosts the actual model inference. Example aliases route to GPT-4.1 and GPT-4.1-mini deployments. The gateway authenticates with its own managed identity. | It does not receive the caller's gateway API key as a model credential. An alias is routing configuration, not another model instance. |
| **Foundry hosted-agent account** | Provides the separate Foundry environment in which an application team can later deploy a hosted agent. | Creating the account does not create a running agent or enable private hosted-agent execution. |
| **Foundry project** | Groups the future agent's connections and provides a project identity with scoped access to its dependencies. | Project permissions do not automatically grant the gateway, a VM or a later agent identity the same access. |
| **Azure Container Registry, Premium** | Stores the container image that a later hosted-agent deployment can pull. Terraform creates the registry and its project connection. | It does not build an image or run containers. An empty registry is expected before application deployment. |
| **Azure Blob Storage** | Supplies a connected data store for agent features that need files or artifacts. The project receives Blob data access. | It is not where the model is hosted; a model-only gateway call does not require a Blob read. The published private profile does not add a Blob private endpoint. |
| **Hosted agent application, later** | Runs agent application code in Foundry Agent Service and can use the same gateway API as other clients. | It is not deployed by this Terraform sample. Image, identity and network connectivity belong to a separate deployment; private-only ingress requires a supported private route and DNS from that runtime. |

Storage and the registry are provisioned even when the first test is just a
model call, because the sample prepares the agent environment as well. Do not
confuse that sample scope with a product requirement for every gateway client.

### Monitoring infrastructure

| Component | Why it is here | Ownership and boundary |
| --- | --- | --- |
| **Gateway Application Insights** | Links the gateway to the configured OpenTelemetry monitoring destination. | Terraform manages the Insights component. Merely creating it is not proof of successful telemetry delivery. |
| **Gateway Log Analytics workspace** | Stores queryable request logs and distributed traces, including `OTelLogs` and `OTelSpans`, for troubleshooting. | Terraform manages the workspace. Query permissions differ from publishing permissions. |
| **Azure Monitor workspace** | Stores the metric time series used for usage and performance charts, queried through Prometheus APIs. | Created by Azure's monitoring enablement, not separately declared as another application stack. It is distinct from Log Analytics. |
| **Data collection endpoint (DCE)** | Provides the ingestion endpoint to which the gateway sends its OpenTelemetry signals. | Azure-managed helper resource. It is not a private endpoint into the model account. |
| **Data collection rule (DCR)** | Routes incoming signals to the correct monitoring destinations. The gateway's publishing permission is scoped to the actual linked rule. | Azure-managed helper resource. Its resource ID and endpoints must be discovered, not guessed. |
| **Agent Application Insights and Log Analytics** | Provide a separate monitoring destination connected to the Foundry agent account. | Terraform provisions the destination; a later application must still emit telemetry. Gateway traces do not prove agent instrumentation works. |

Application resources use one shared resource group. Monitoring enablement can
create additional **Azure-managed helper groups**, with separate costs and
ownership. See [monitoring setup](monitoring.md) for the required two-stage
configuration. Payload capture is disabled; this is not a claim that every
telemetry field is free of operational information.

## 2. Base private connectivity

**Ownership:** in `create` mode the sample manages the network/DNS
foundation. In `existing` mode those resources remain platform-owned.
The platform also retains its central resolver, routes, firewall and zone links.
There is no requirement for one VNet or a direct DNS-zone link to every
spoke. Approved existing endpoint subnets may differ by service. In both modes
the workload creates the private endpoints, while their DNS zone groups have
one explicitly chosen workload or platform owner.

There are **two different private paths**:

1. **Client to gateway:** a client with VNet connectivity resolves the gateway
   hostname to its private endpoint and authenticates with an Entra token or
   a gateway API key. Entra callers also require the invocation role.
2. **Gateway to model:** the gateway uses outbound VNet integration to reach the
   model's private endpoint, then authenticates with its managed identity.

These are network routes, not replacements for authentication.

| Component | Why it is here | Important distinction |
| --- | --- | --- |
| **Virtual network and subnets** | Separate the optional test client, private endpoints and the gateway's outbound integration. | The PaaS gateway and model account are not deployed inside these subnets. |
| **Gateway private endpoint** | Gives private clients a private IP through which to reach the gateway. | The `private-only` profile separately disables public ingress. An approved endpoint alone does not disable it; provisioning is incomplete until public access is disabled. |
| **Outbound VNet integration and connector gateway** | Give the gateway an outbound route into the VNet so it can reach private backends. `Microsoft.Web/connectorGateways` is supporting gateway infrastructure. | This is not another model proxy or an Azure Application Gateway. |
| **Model private endpoint** | Connects the VNet to the model account while model public access is disabled. | A working gateway private endpoint alone does not establish this backend route. |
| **Private DNS zones and VNet links** | Resolve gateway and model hostnames to the private endpoint addresses for VNet-connected clients. | Clients using custom DNS need an appropriate forwarding path. A `services.ai` DNS zone does not create private hosted-agent execution. |
| **Optional test VM** | Provides a controlled private client for DNS, network and inference checks, with no public IP. | It is a probe, not production application compute. Use an existing suitable client instead; stop the VM when it is not needed. |

**Private-only gateway ingress is an explicit end state, not the default.**
The `private-only` profile disables gateway and model public access; the
intermediate `private-connectivity` profile disables only model public access
and is not an accepted final deployment.
These base ingress profiles do not configure agent network injection or a
private Blob endpoint. Base agent infrastructure alone is not a verified
private runtime path. For new private agent deployments, explicitly enable
the configuration below from the start; unrelated existing agents need no
migration for this reference scenario.
See [private connectivity](private-connectivity.md) and
[platform-team prerequisites](../README.md#platform-team-policy-compatibility).

### End-to-end private request flow

This logical successful-request sequence uses **existing central DNS** and the
gateway/model **`private-only` target after approved staged setup**. It is a runtime
reference, not a deployment sequence or evidence of acceptance in a particular environment.

| Step | Exchange | Purpose |
| --- | --- | --- |
| 1 | Application to Microsoft Entra ID | Request a token for the gateway audience when using Entra client authentication. |
| 2 | Microsoft Entra ID to application | Return the caller's gateway access token. |
| 3 | Application to central DNS resolver | Resolve the gateway hostname. |
| 4 | Central DNS resolver to application | Return the gateway private endpoint address through the configured DNS path. |
| 5 | Application to AI Gateway | Send the model request over HTTPS through the gateway private endpoint, with the caller's token or API key. |
| 6 | Within AI Gateway | Validate access and, for Entra callers, the invocation role; evaluate policies and resolve the model alias. A rejected request does not proceed to inference. |
| 7 | AI Gateway to central DNS resolver | Resolve the selected model backend hostname through the configured DNS path. |
| 8 | Central DNS resolver to AI Gateway | Return the model private endpoint address. |
| 9 | Gateway identity to identity service | Acquire a backend token using the gateway's separate managed identity. |
| 10 | Identity service to gateway | Return the backend access token, distinct from the caller's token. |
| 11 | AI Gateway to Foundry model | Send the authenticated inference request through outbound VNet integration and the model private endpoint. |
| 12 | Foundry model to AI Gateway | Return the model response or stream after backend authorization. |
| 13 | AI Gateway to application | Return the response or stream over the established client connection. |

With **API-key client authentication**, skip the initial client token exchange
(steps 1 and 2). The gateway still uses its **separate managed identity** for the
model call; the model validates that backend identity's authorization. Private
endpoints and VNet integration provide transport; they are not additional
application services processing the prompt.

DNS results and tokens may be cached, and acquisition order can vary. This sequence
does not prescribe a managed-identity broker endpoint or imply that Entra,
control-plane or telemetry connections are private. Error, policy-denial,
throttling and retry branches are omitted. For the specialized agent key flow
see [private-agent authentication](#4-current-private-agent-authentication);
for token audiences and invocation roles see the
[Entra sequence](#5-target-request-sequence-with-microsoft-entra-id).

## 3. Private agent reference

The request path is **private client to hosted agent to gateway to model**;
container-image and monitoring dependencies are separate. This configuration was used by the
[successful October 25 deployment](private-hosted-agent.md#observed-deployment-and-proof):
a private client invoked a hosted agent, which called the private gateway and
model backend. The response was **OK**, both gateway and backend spans had
**HTTP 200** under one trace, and an authenticated public gateway call received
a network-denial **HTTP 403**. Actual subnet ranges come from the approved VNet inputs.

| Surface | Configured when | Boundary |
| --- | --- | --- |
| Basic Foundry account, project and agent subnet injection | Account creation with `enable_private_hosted_agent = true` | Injection supplies runtime outbound connectivity; it cannot be added to an existing account. |
| Foundry private endpoint | Infrastructure deployment | Inbound project access, not runtime outbound injection. |
| ACR private endpoint and DNS | Infrastructure deployment | Both registry login and regional data names must resolve privately; the registry's public-access setting is not changed by this extension. |
| Agent application and image | Separate application deployment | Terraform does not create the agent version. The proof reused an immutable image digest. |
| Runtime gateway key-reader and AcrPull | After discovering the runtime principal | Runtime identity is distinct from the project and executor identities. |
| Existing private gateway, model route and monitoring | Reused | No extra model, direct-model fallback, or new monitoring stack. |

The PaaS services are **not resources physically placed in the endpoint
subnet**. Endpoint, client, gateway-integration and delegated agent
subnets have separate roles. Basic agent data remains Azure-managed and multitenant,
not in separately provisioned Cosmos DB, Search or Storage resources. A private Blob endpoint is
not a dependency of the demonstrated agent model call.

This is a reference for **new agent deployments**, not a requirement to migrate
an existing test agent. Explicitly select the private configuration and
complete all application/identity stages. Public Terraform defaults, legacy
gateway resource compatibility and region/policy acceptance requirements remain.

## 4. Current private-agent authentication

The runtime identity retrieves a gateway key from ARM into runtime memory. The
agent uses that key over the private route; the gateway uses its own managed
identity for the model.

| Hop | Credential | Required permission |
| --- | --- | --- |
| Private client to Foundry | Client's Entra token; the observed executor used managed identity | Foundry User on the selected project. |
| Agent runtime to ARM | Runtime managed-identity token for ARM | Narrow gateway role containing only `Microsoft.ApiManagement/service/apiKeys/listSecrets/action`. |
| Agent runtime to gateway | API key retrieved into runtime memory | Valid gateway key **and** private DNS/network reachability. |
| Gateway to model | Gateway's own managed-identity token | Foundry User on the model account. |
| Runtime image pull | Runtime identity | AcrPull on the registry; verify separately from project AcrPull. |
| Gateway to monitoring | Gateway identity with the Monitor audience | Monitoring Metrics Publisher on the linked DCR. |

The live trace proves gateway/backend request handling, not agent-side
instrumentation, every alias, every preview invocation ingress surface, or
completely private identity/control-plane/telemetry traffic. No NAT, firewall,
AMPLS or deny-all egress policy was added. Foundry public access was disabled
and invocation worked from the private client; independently validate the
preview invocation endpoint's ingress boundary for each new deployment.

<a id="3-request-sequence-with-microsoft-entra-id"></a>

## 5. Target request sequence with Microsoft Entra ID

**Optional caller configuration, live-tested with managed identity.** The
specialized private-agent reference retains the tested API-key flow; the
general private request flow also supports Entra callers. Terraform supports
additive Entra caller roles through `gateway_access_principals`; the client probe
selects Entra with `-Authentication EntraId`. This section details that
caller's token flow. A separate private-VM probe returned 403 without the invocation
role and 200 for both aliases after Terraform granted it, with matching gateway
and backend traces. API-key calls remained successful. The temporary role was
removed and the VM deallocated; existing keys and the deployed agent are unchanged.
This proof does not cover custom delegated-user clients.

**Network prerequisite:** with `private-only`, the application must resolve and
reach the gateway private endpoint before an authenticated model call
can succeed. Entra tokens do not bypass network restrictions. Token acquisition
uses the caller's separate connectivity to Entra; Entra is not behind the
gateway's private endpoint.

This follows the request-lifecycle structure in
[Govern, secure, and operate AI Gateway tier](https://learn.microsoft.com/en-us/azure/api-management/ai-gateway-govern-secure-assets#governance-policies),
with **Entra ID instead of a runtime key** on the inbound request. Current
inbound token and role details are documented in the
[AI Gateway portal security and identity guide](https://ai.gateway.azure.com/docs/security-identity).
The linked Learn lifecycle illustration still uses a runtime key; it is not the
source for the newer inbound Entra settings.

### The three trust boundaries

| Hop | Identity and credential | Permission |
| --- | --- | --- |
| **Application to gateway** | The caller obtains a token for audience `https://azure-api.net/aigateway` and sends `Authorization: Bearer <access-token>`. | **AI Gateway Models User**, role ID `a6b68e3d-a1f0-4c60-8678-237c050cf4ea`, at the required model alias or gateway scope. A management role alone is not invocation access. |
| **Gateway to Foundry model** | The gateway obtains a **different token**, using its own managed identity, for the configured Cognitive Services audience. | **Foundry User**, role ID `53ca6127-db72-4b80-b1b0-d745d6d5456d`, on the model account. This is already configured by the sample. |
| **Gateway to monitoring** | The gateway identity publishes OpenTelemetry for the Monitor audience, independently of the caller token. | **Monitoring Metrics Publisher** on the actual linked DCR. This is separate from model invocation and query access. |

The caller token is **not** forwarded to the model; no on-behalf-of token
exchange is shown. Client, gateway and project identities remain distinct.
Token acquisition and refresh can use caches, so the token exchanges
are not necessarily new network round trips for every prompt.

### What must change before using the Entra target flow

The platform team can use the [Access input](reference.md#access) to assign the
supported **invocation role** in the gateway subscription's tenant. This map
grants all-model access at gateway scope; use a separately reviewed alias-scoped
assignment instead when the application needs only one model. The application team must obtain a token
for the gateway audience and replace its `api-key` header with the Bearer header.
Do not send an ARM management token or a model-backend token to the gateway.

For a **custom application signing in users**, the portal guide additionally
requires the Azure AI Gateway Dataplane delegated permission **Data.All** and
consent. Request `https://azure-api.net/aigateway/Data.All`; the signed-in user
also needs the appropriate Azure RBAC invocation role. The guide identifies the
dataplane application as `18550318-e177-4205-a743-6816d6fcdc3f`.
This delegated-permission setup is not the flow for managed identities or
service principals using client credentials.

For a workload calling as itself, use its supported application or managed
identity token-acquisition flow and assign the invocation role to that workload
identity. Confirm availability, token acquisition, role propagation and client
compatibility against the target preview gateway before changing production
authentication. Removing or revoking existing keys is a separate, reviewed
migration step; this documentation does not do it.

### Policy and monitoring behavior

**Policies is a logical lane inside AI Gateway, not a separate Azure service.**
The sample configures a per-caller model token limit. The product also supports
other policies, but this reference does not claim that they are all provisioned:

| Rejection | Response documented by the service |
| --- | --- |
| Content safety, when configured | 400 |
| IP filter, when configured | 403 |
| Token or request rate limit | 429 with `Retry-After` |

Authentication and invocation authorization are checked before backend
inference. A policy denial stops the model call. A backend can return its own
errors, including quota limits; not every 429 is a gateway policy rejection.
Telemetry export is asynchronous; the response does not wait for successful
ingestion. Payload capture remains disabled.

These branches describe intended behavior, not evidence of new negative,
load or Entra-runtime tests. Verify the migrated caller with the
[acceptance guide](acceptance.md), including allowed and denied identities,
the intended network route and fresh telemetry. A successful model response
alone is not complete acceptance.

## 6. Deployment responsibility

| Stage | Owner | Result |
| --- | --- | --- |
| Policy, permissions and networking review | Platform team | Approved regions, resource types, identity permissions and reachable dependencies. |
| Terraform infrastructure and monitoring setup | Platform team | Gateway, model deployments and aliases, Foundry account/project, Storage, registry, roles and monitoring; private routing when the private profile is selected. |
| Agent image and application deployment, if needed | Application team | A running hosted agent using the prepared infrastructure. This is separate from Terraform. |
| Runtime identity binding | Platform and application teams | Discovered runtime principal has gateway key-read and registry pull access; retain the binding inputs for future Terraform plans. |
| Runtime and portal verification | Platform and application teams | Evidence for inference, authentication, intended network paths and fresh telemetry. |

<a id="diagram-sources-and-icon-provenance"></a>

## Documentation scope

The architecture and request flows are documented directly in these guides.
Separate graphic exports, editable diagram sources and rendering tools are not
included in the published checkout and are not required for deployment or its
verification. Optional offline artwork remains subject to the
[Azure icon terms](https://learn.microsoft.com/en-us/azure/architecture/icons/#icon-terms)
and [Microsoft Entra icon guidance](https://learn.microsoft.com/en-us/entra/architecture/architecture-icons).
