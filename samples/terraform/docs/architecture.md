# Architecture: what each service does

For a model call, the application asks a question, the gateway checks and routes
the request, and the model generates the answer. This guide explains that core
path, its transport and identity boundaries, and the optional agent extension.
The gateway is neither the model host nor the agent runtime.

For execution, use the [shared operator procedure](../01-04-deployment.md#runbook-order);
for file-role basics, use [Understand the sample](understand-the-sample.md).
The [preview and resource constraints](reference.md#resource-type-and-lifecycle)
still apply. Architecture is not evidence that a particular deployment is ready.

**Illustrations:**
[Overall architecture](../README.md#existing-network-reference-architecture) |
[Network and DNS](../01-04-deployment.md#existing-network-connectivity-reference) |
[Resource ownership](../01-04-deployment.md#platform-handoff-before-a-plan).

<a id="1-base-sample-architecture"></a>

## Core sample architecture

The core model-call path is the same in Public and Private-only deployments:

```text
Application -> AI Gateway -> Foundry model
```

The response returns along the same path. Telemetry is exported separately;
it is not part of the synchronous model response. Configured connections and
permissions are **not proof of data flowing**. A simple application or the
gateway Playground can call a model without running an agent.

### Runtime and application infrastructure

| Component | Why it is here | What it does not do |
| --- | --- | --- |
| **AI Gateway** | Provides one model API endpoint. It validates a runtime API key or Entra token and invocation role, resolves aliases such as `gpt-mini`, enforces a token budget per caller identity and forwards the request. | It does not execute the model or agent code. It is not Azure Application Gateway, and no Application Gateway is deployed here. |
| **Foundry model account and deployments** | Hosts the actual model inference. Example aliases route to GPT-4.1 and GPT-4.1-mini deployments. The gateway authenticates with its own managed identity. | It does not receive the caller's gateway API key as a model credential. An alias is routing configuration, not another model instance. |
| **Base Foundry hosted-agent account** | Provides the separate Foundry environment in which an application team can later deploy a hosted agent. | Creating the account does not create a running agent or enable private hosted-agent execution. |
| **Base Foundry project** | Groups the future agent's connections and provides a project identity with scoped access to its dependencies. | Project permissions do not automatically grant the gateway, a VM or a later agent identity the same access. |
| **Azure Container Registry, Premium** | Stores the container image that a later hosted-agent deployment can pull. Terraform creates the registry and its project connection. | It does not build an image or run containers. An empty registry is expected before application deployment. |
| **Azure Blob Storage** | Supplies a connected data store for agent features that need files or artifacts. The project receives Blob data access. | It is not where the model is hosted; a model-only gateway call does not require a Blob read. The published private profile does not add a Blob private endpoint. |
| **Hosted agent application, later** | Runs agent application code in Foundry Agent Service and can use the same gateway API as other clients. | It is not deployed by this Terraform sample. Image, identity and network connectivity belong to a separate deployment; private-only ingress requires a supported private route and DNS from that runtime. |

The base agent account/project, Storage and Premium registry are **unconditional
core sample resources**, even for a first model-only test. This is the sample's
scope, not a product requirement for every gateway client. The optional private
agent extension adds **another account/project**; it does not replace the base
resources or make Terraform run an agent.

### Ownership and access are independent

| Choice | What it controls | What it does not imply |
| --- | --- | --- |
| Network ownership: `create` or `existing` | Whether this root creates the VNet/subnet/DNS foundation or consumes approved platform IDs. | Selecting `existing` does not enable private networking. Existing-resource ownership is not transferred to the workload. |
| Network access: Public or Private-only | Whether gateway/model public access remains enabled or is closed after approved private setup. | Private-only does not make all supporting services private. |

`private-connectivity` is an **intermediate new-deployment profile** that enables
gateway public access while disabling model public access. It is not a final
private state or an already-private maintenance profile. Ownership and access
files must be composed explicitly; later object values replace whole objects,
not individual nested fields. See [input composition](../01-04-deployment.md#compose-the-inputs).

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

<a id="2-base-private-connectivity"></a>

## Private transport and DNS

In `existing` mode, the platform retains the network/DNS foundation, central
resolver, routes, firewall and zone links. There is no requirement for one VNet
or a direct zone link to every spoke. Approved endpoint subnets may differ by
service. In either ownership mode the workload creates private endpoints;
their zone groups have **one** chosen workload or platform owner. Central zone
ownership and zone-group association ownership are different responsibilities.

The shared root separates [foundation creation](../private-network.tf) from
[workload endpoints and associations](../private-endpoints.tf), with resolved
IDs in [network context](../private-network-context.tf). All files load together;
the split creates no modules, new states or ownership transfer.

There are two private transport paths: **client to gateway** through the gateway
private endpoint, and **gateway to model** through outbound VNet integration
and the model private endpoint. Each still needs its own authentication.

| Component | Why it is here | Important distinction |
| --- | --- | --- |
| **Virtual network and subnets** | Separate the optional test client, private endpoints and the gateway's outbound integration. | The PaaS gateway and model account are not deployed inside these subnets. |
| **Gateway private endpoint** | Gives private clients a private IP through which to reach the gateway. | The `private-only` profile separately disables public ingress. An approved endpoint alone does not disable it; final private-only acceptance requires closure. |
| **Outbound VNet integration and connector gateway** | Give the gateway an outbound route into the VNet so it can reach private backends. `Microsoft.Web/connectorGateways` is supporting gateway infrastructure. | This is not another model proxy or an Azure Application Gateway. |
| **Model private endpoint** | Connects the VNet to the model account while model public access is disabled. | A working gateway private endpoint alone does not establish this backend route. |
| **Private DNS zones and VNet links** | Resolve gateway and model hostnames to the private endpoint addresses for VNet-connected clients. | Clients using custom DNS need an appropriate forwarding path. A `services.ai` DNS zone does not create private hosted-agent execution. |
| **Optional test VM** | Provides a controlled private client for DNS, network and inference checks, with no public IP. | It is a probe, not production application compute. An approved existing client is sufficient for manual acceptance; a new VM is not mandatory. |

The core contract has **three subnet input fields**, which may use two physical
subnets when the two endpoints share one. The four required DNS-zone IDs serve
gateway/model names; they do not represent four endpoints.

**Private-only is an explicit staged end state, not the default.** It closes
gateway/model public access, not all supporting services. The base agent account
and registry remain publicly enabled; Storage defaults to public access unless
an approved restriction is configured. The ingress profiles do not add agent
injection or a Blob private endpoint. Required supporting-service restrictions
need working connectivity for every consumer, as described in the
[Policy handoff](../01-04-deployment.md#platform-team-policy-compatibility).
Use [private connectivity](private-connectivity.md) for the actual staged procedure.

### End-to-end private request flow

This logical successful-request sequence uses **existing central DNS** and the
gateway/model **`private-only` end state after approved staged setup**. It is a
runtime reference, not a deployment sequence or target-environment acceptance.

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

With **API-key client authentication**, skip the initial token exchange (steps
1 and 2). The gateway still uses its **separate managed identity** for the model
call. Private endpoints and VNet integration provide transport; they are not
extra application services processing the prompt.

DNS and tokens may be cached, and acquisition order can vary. This sequence
does not prescribe a managed-identity broker endpoint or imply that Entra,
control-plane or telemetry connections are private. Error, policy-denial,
throttling and retry branches are omitted. The authentication boundaries follow;
the [specialized agent key flow](#private-agent-api-key-flow) comes later.

<a id="3-request-sequence-with-microsoft-entra-id"></a>
<a id="5-target-request-sequence-with-microsoft-entra-id"></a>

## Current authentication and policy boundaries

**API keys and Entra are current, additive caller alternatives.** Entra callers
present a token for the gateway audience and need an invocation role; keys are
not removed when those roles are added. Management access alone is not model
invocation access. Both alternatives require the selected network route.
Token acquisition uses separate connectivity to Entra, not the gateway endpoint.

### The three trust boundaries

| Hop | Identity and credential | Permission |
| --- | --- | --- |
| **Application to gateway** | Caller gateway API key, or an Entra token for the gateway audience. | A valid key, or **AI Gateway Models User** at the approved alias/gateway scope. The sample's optional principal map grants all-model invocation at gateway scope. |
| **Gateway to Foundry model** | The gateway obtains a **different token** using its own managed identity for the configured Cognitive Services audience. | **Foundry User** on the model account, already configured by the sample. |
| **Gateway to monitoring** | The gateway identity publishes OpenTelemetry for the Monitor audience, independently of the caller token. | **Monitoring Metrics Publisher** on the actual linked DCR, separate from model invocation and query access. |

The caller token is **not forwarded** to the model; no on-behalf-of exchange is
shown. Client, gateway and project identities remain distinct. Token acquisition
and refresh may use caches rather than a new round trip for every prompt.

<a id="what-must-change-before-using-the-entra-target-flow"></a>

For optional caller inputs, object-ID lookup, exact audiences/roles and
delegated-user consent, use [Access](reference.md#access). Existing gateways use
the [update preflight](../01-04-deployment.md#update-an-existing-gateway), not bootstrap
or an automatic key-removal migration.

<a id="policy-and-monitoring-behavior"></a>

### Policy boundaries

**Policies are a logical lane inside AI Gateway, not a separate Azure service.**
The sample configures a per-caller model token limit. The product supports other
policies, but this reference does not claim that they are all provisioned:

| Rejection | Response documented by the service |
| --- | --- |
| Content safety, when configured | 400 |
| IP filter, when configured | 403 |
| Token or request rate limit | 429 with `Retry-After` |

Authentication and invocation authorization are checked before backend inference;
a policy denial stops the model call. Backends can return their own errors,
including quota limits, so not every 429 is a gateway policy rejection.
See the [service request lifecycle](https://learn.microsoft.com/en-us/azure/api-management/ai-gateway-govern-secure-assets#governance-policies)
for policy behavior; its key-based illustration is not the newer inbound Entra
configuration contract. Intended behavior is not evidence of negative or load tests.

## Monitoring infrastructure

Telemetry export is **asynchronous**: a successful response does not wait for
successful ingestion. Payload capture remains disabled, but this is not a claim
that every telemetry field is free of operational information.

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
ownership. [Monitoring setup](monitoring.md) owns the two-stage procedure.
Fresh correlated traces and the portal metrics comparison remain acceptance gates.

<a id="6-deployment-responsibility"></a>

## Deployment responsibility

| Stage | Owner | Result |
| --- | --- | --- |
| Policy, permissions and networking review | Platform team | Approved regions, resource types, identity permissions and reachable dependencies; recorded in the [pre-plan handoff](../01-04-deployment.md#platform-handoff-before-a-plan). |
| Terraform infrastructure and monitoring setup | Platform team | Gateway, model deployments and aliases, base Foundry account/project, Storage, registry, roles and monitoring; private routing when explicitly selected. |
| Agent image and application deployment, if needed | Application team | A running hosted agent using the prepared infrastructure, separate from Terraform. |
| Runtime identity binding, if needed | Platform and application teams | Discovered runtime principal has gateway key-read and registry pull access; binding inputs are retained for future plans. |
| Runtime and portal verification | Platform and application teams | Evidence for inference, authentication, intended network paths and fresh telemetry, with [handover owners and cleanup](acceptance.md#complete-the-acceptance-record). |

<a id="3-private-agent-reference"></a>

## Optional private hosted-agent architecture

The optional path is **private client to hosted agent to gateway to model**.
The extension adds a separate VNet-injected Basic Foundry account/project, not
another model or gateway. Image, identity and application deployment are still
separate work. Use the [agent deployment gates](private-hosted-agent.md#deployment-and-acceptance-gates)
when this runtime is actually required.

| Surface | Configured when | Boundary |
| --- | --- | --- |
| Additional Basic Foundry account/project and agent subnet injection | Account creation with `enable_private_hosted_agent = true` | Injection supplies runtime outbound connectivity; it cannot be added to an existing account. |
| Foundry private endpoint | Infrastructure deployment | Inbound project access, not runtime outbound injection. |
| ACR private endpoint and DNS | Infrastructure deployment | Both registry login and regional data names must resolve privately; the registry's public-access setting is not changed by this extension. |
| Agent application and image | Separate application deployment | Terraform does not create the agent version or image. |
| Runtime gateway key-reader and AcrPull | After discovering the runtime principal | Runtime identity is distinct from the project and executor identities. |
| Existing private gateway, model route and monitoring | Reused | No extra model, direct-model fallback or new monitoring stack. |

PaaS services are **not physically placed in the endpoint subnet**. Endpoint,
client, gateway-integration and delegated agent subnets have different roles;
actual ranges come from approved inputs. Basic agent internal data remains
Azure-managed and multitenant, without adding dedicated Cosmos DB, Search or
Storage resources. The core sample Storage account still exists for connected
artifact features; a Blob private endpoint was not a dependency of the
recorded agent model call.

This is an opt-in architecture for **new private agent accounts**, not a
requirement to migrate unrelated existing agents. The public defaults,
gateway compatibility and region/Policy gates still apply.

<a id="4-current-private-agent-authentication"></a>

### Private-agent API-key flow

The recorded agent runtime retrieves a gateway key from ARM into runtime memory,
then uses it over the private route. It has not been migrated to Entra gateway
invocation; the gateway still uses its own managed identity for the model.

| Hop | Credential | Required permission |
| --- | --- | --- |
| Private client to Foundry | Client's Entra token; the observed executor used managed identity | Foundry User on the selected project. |
| Agent runtime to ARM | Runtime managed-identity token for ARM | Narrow gateway role containing only `Microsoft.ApiManagement/service/apiKeys/listSecrets/action`. |
| Agent runtime to gateway | API key retrieved into runtime memory | Valid gateway key **and** private DNS/network reachability. |
| Gateway to model | Gateway's own managed-identity token | Foundry User on the model account. |
| Runtime image pull | Runtime identity | AcrPull on the registry; verify separately from project AcrPull. |
| Gateway to monitoring | Gateway identity with the Monitor audience | Monitoring Metrics Publisher on the linked DCR. |

The recorded proof did not add NAT, firewall, AMPLS or deny-all egress policy.
It does not establish every preview invocation endpoint's ingress boundary,
agent-side instrumentation or completely private identity/control-plane/telemetry
traffic. Validate those required boundaries for each deployment.

## Evidence and operational next steps

Historical results are scoped observations, not generic customer readiness:

| Evidence | Scope and remaining boundary |
| --- | --- |
| [Private-only ingress results](reference.md#private-only-gateway-ingress-status) | Observed October gateway closure and the isolated existing-network rehearsal; not private-from-first-create or proof for another environment. |
| [Entra caller results](reference.md#access) | Managed-identity calls and negative controls; not custom delegated-user verification or an agent authentication migration. |
| [Private-agent proof](private-hosted-agent.md#observed-deployment-and-proof) | The recorded private agent version/image and gateway/backend trace; not every alias, runtime dependency or preview ingress surface. |

Deploy or maintain through the [operator runbook](../01-04-deployment.md#runbook-order).
Select [manual acceptance](acceptance.md) for an approved existing client, or the
[optional sample-VM runner](end-to-end.md) only when that VM exists. The runner
reads Azure, plans and writes reports; explicit runtime checks can start the VM,
use Run Command and incur inference/compute costs. Complete the selected route,
fresh telemetry and [handover record](acceptance.md#complete-the-acceptance-record);
a model response alone is not complete acceptance.

<a id="diagram-sources-and-icon-provenance"></a>

## Documentation scope

The architecture and request flows are documented directly in these guides.
The illustrations embedded in the [overview](../README.md) and
[deployment guide](../01-04-deployment.md) are included as self-contained SVGs, with
links to the full-size images. Additional image exports, editable diagram
sources and rendering tools remain local and are not required for deployment
or its verification. The illustrations use official service artwork under the
[Azure icon terms](https://learn.microsoft.com/en-us/azure/architecture/icons/#icon-terms)
and [Microsoft Entra icon guidance](https://learn.microsoft.com/en-us/entra/architecture/architecture-icons).
