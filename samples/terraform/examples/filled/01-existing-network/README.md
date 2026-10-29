# Scenario 01: filled input reference for existing networking

[Back to Scenario 01](../../../docs/scenarios/01-existing-network.md)

Use this reference to understand how the inputs fit together when the **gateway
workload is new**, but networking and central Private DNS already belong to the
platform team. The intended end state is private gateway/model access after the
approved deployment stages. This filled variant selects **Entra caller access
with Terraform-managed role assignments, private Blob connectivity, private
Hosted Agent infrastructure and a new private test VM**. These choices belong
to this walkthrough; they are not mandatory defaults for every Scenario 01
deployment.

> [!CAUTION]
> Subscription/object IDs, resource names, contacts and capacity values below are
> fictional. This is a reading aid, not approved deployment input or a separate
> deployment procedure. Do not pass this Markdown file to Terraform.

## Color key

The labels carry the meaning even when colors are unavailable.

| Marker | What to do |
| --- | --- |
| &#x1F7E2; **ACTIVE** | The assignment is active in this reference. Use it without `#` in the protected working inputs, replacing illustrative values and leaving explanatory comments alone. |
| &#x1F535; **PROFILE** | Set the value through the selected network or access input file, not through a duplicate assignment in the base file. |
| &#x1F534; **NOT THIS SCENARIO** | Do not activate settings that create a parallel network/DNS foundation. |

In HCL, `#` starts a comment. **Never remove every `#`**: explanation text must
remain commented. The selected assignments in the
[Scenario 01 base example (`01-terraform.tfvars.example`)](./01-terraform.tfvars.example)
are already active, including the complete Entra block and selected private
features; no further uncommenting is needed in that file. The shared
Base template (`01-04-terraform.tfvars.example`) still comments out these
extensions because it supports other scenarios; its defaults are unchanged.

## Filled base inputs

&#x1F7E2; **ACTIVE** - these are the assignment lines in the base input file.
Use the
[Scenario 01 base example (`01-terraform.tfvars.example`)](./01-terraform.tfvars.example)
for this walkthrough. It already combines the base values below, the
[required Entra caller access](#required-entra-caller-access) and the
[selected private features](#selected-private-features) in one file.
The sections below explain those assignments; **do not append them a second
time** to the example.

If no approved workload input file exists, use a protected working copy such
as `terraform.tfvars` and replace the illustrative values before use.
The `.example` file is not loaded automatically. The
[shared Base template (`01-04-terraform.tfvars.example`)](../../../01-04-terraform.tfvars.example)
remains the generic starting point for other selections.

```hcl
subscription_id = "11111111-2222-4333-8444-555555555555"

environment_name = "demo-ai-gateway"

location         = "swedencentral"
gateway_location = "swedencentral"

publisher_email = "platform-team@example.com"

model_deployments = {
  gpt-mini = {
    model_name    = "gpt-4.1-mini"
    model_version = "2025-04-14"
    sku_name      = "GlobalStandard"
    capacity      = 10
    token_limit   = 5000
  }

  gpt-full = {
    model_name    = "gpt-4.1"
    model_version = "2025-04-14"
    sku_name      = "GlobalStandard"
    capacity      = 10
    token_limit   = 10000
  }
}
```

| Field | How to choose the real value |
| --- | --- |
| `subscription_id` | Approved workload subscription UUID, not its display name or the Tenant ID. Selecting it does not authenticate you or grant access. |
| `environment_name` | Agreed workload label, not an existing resource-group ID. Use 1-32 lowercase letters, digits or hyphens, starting with a letter. Do not casually rename a deployed workload. |
| `location`, `gateway_location` | Both are intentionally `swedencentral` in this example. Confirm regional service availability, preview enablement and quota before a real run. |
| `publisher_email` | Approved operational contact. This is not a login identity. |
| `model_deployments` | Approved model versions and capacity. `gpt-mini` and `gpt-full` are the caller-facing deployment names; `model_name` identifies the model. |

The model identifiers are real technical identifiers taken from the
Base template (`01-04-terraform.tfvars.example`), **not a fresh availability or
quota confirmation**. `sku_name` is the model deployment SKU; it does not change
the sample's gateway SKU.
`GlobalStandard` does not guarantee processing only in Sweden.
`capacity` is model-deployment capacity, not a price or the gateway caller limit;
`token_limit` is a separate gateway token limit.

**The base file does not supply network ownership or the gateway/model access
stage.** The complete network input file and the approved stage-specific access
settings are also required.

## Filled existing-network inputs

&#x1F535; **PROFILE** - this illustrates the contents of the protected
environment copy of
[01-04-profiles/network-existing.tfvars.json](../../../01-04-profiles/network-existing.tfvars.json).
JSON has no `#` comments: every entry below is an assignment when that file is
explicitly selected.

**This walkthrough uses eight subnet-ID fields referring to five distinct
existing subnets, plus six central Private DNS zones.** The linked profile is a
core-only starting template. The complete example below also includes the
network inputs for our selected private Blob connectivity, private Hosted Agent
infrastructure and new private test VM; do not replace it with the smaller
core-only object while those features are enabled.

```json
{
  "private_network_mode": "existing",
  "private_dns_zone_group_management": "workload",
  "existing_private_network": {
    "gateway_subnet_id": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-network/providers/Microsoft.Network/virtualNetworks/vnet-demo-gateway/subnets/snet-gateway-outbound",
    "agent_subnet_id": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-network/providers/Microsoft.Network/virtualNetworks/vnet-demo-models/subnets/snet-agents-outbound",
    "client_subnet_id": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-network/providers/Microsoft.Network/virtualNetworks/vnet-demo-gateway/subnets/snet-test-clients",
    "endpoint_subnet_ids": {
      "gateway": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-network/providers/Microsoft.Network/virtualNetworks/vnet-demo-gateway/subnets/snet-gateway-private-links",
      "models": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-network/providers/Microsoft.Network/virtualNetworks/vnet-demo-models/subnets/snet-model-private-links",
      "storage": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-network/providers/Microsoft.Network/virtualNetworks/vnet-demo-models/subnets/snet-model-private-links",
      "agents": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-network/providers/Microsoft.Network/virtualNetworks/vnet-demo-models/subnets/snet-model-private-links",
      "registry": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-network/providers/Microsoft.Network/virtualNetworks/vnet-demo-models/subnets/snet-model-private-links"
    },
    "private_dns_zone_ids": {
      "gateway": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-dns/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net",
      "cognitiveservices": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-dns/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com",
      "openai": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-dns/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com",
      "services": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-dns/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com",
      "storage": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net",
      "registry": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-dns/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
    }
  }
}
```

All shown resource IDs refer to **fictional existing platform resources**, not
resources this example asks Terraform to create. Obtain the actual IDs and
readiness confirmation from the platform owner using the
[field-by-field mapping and Portal lookup](../../../01-04-deployment.md#find-resource-ids-and-fill-in-the-network-input-file).
DNS zone IDs are not Private DNS Resolver IDs.

| Setting in this walkthrough | Required platform agreement or verification |
| --- | --- |
| Eight subnet-ID fields, five existing subnets | All eight fields are included in the JSON above and mapped below. The platform must approve the five subnets and their use, including shared endpoint placement. Existing does not mean available or compatible. |
| Subscription in subnet IDs | The example uses the same fictional subscription as the base file. The sample requires endpoint subnets in the workload subscription. |
| Six central DNS zones | Four core zones plus `storage` and `registry` are required for the selected features. The agent endpoint reuses the core Cognitive Services/OpenAI/services zones; there is no separate `agents` DNS-map key. Zone count is not endpoint count. Replace the subscription/group IDs; central zones may be in another subscription with the required permissions. |
| `"private_dns_zone_group_management": "workload"` | This is an illustrative ownership choice, not a customer decision. Use `workload` only when the workload may create endpoint-to-zone associations; use `platform` when platform automation owns them. Neither transfers ownership of central zones, VNet links or the resolver. |

The network file chooses **ownership**, not an access stage. Keep the complete
`existing_private_network` object: a later assignment replaces the whole object,
not just its changed fields.

<a id="three-core-input-fields-two-or-three-core-subnets"></a>

### Eight subnet-ID fields, five existing subnets

All eight fields below belong to `existing_private_network` and are required
for the selected setup in this walkthrough. This is the complete subnet-input
list, not just the gateway/model core:

| Field | Purpose | Subnet in the filled example |
| --- | --- | --- |
| `gateway_subnet_id` | Gateway outbound VNet integration, used to reach private backends. | `snet-gateway-outbound` |
| `agent_subnet_id` | Separate outbound VNet integration for the private Hosted Agent infrastructure. | `snet-agents-outbound` |
| `client_subnet_id` | Subnet for the new private test VM, not automatically the production application's subnet. | `snet-test-clients` |
| `endpoint_subnet_ids.gateway` | Gateway private endpoint: the private entry point used by callers. | `snet-gateway-private-links` |
| `endpoint_subnet_ids.models` | Model-service private endpoint, reached by the gateway. | `snet-model-private-links` |
| `endpoint_subnet_ids.storage` | Blob Storage private endpoint. | `snet-model-private-links` |
| `endpoint_subnet_ids.agents` | Private endpoint for the additional private Hosted Agent infrastructure. | `snet-model-private-links` |
| `endpoint_subnet_ids.registry` | Container registry private endpoint. | `snet-model-private-links` |

**Why eight fields but five subnets?** The model, Blob, agent and registry
endpoint fields all reference the same `snet-model-private-links` subnet.
Gateway integration, gateway endpoints, agent integration and the test client
each use a separate subnet in this example. Shared endpoint placement requires
platform approval and sufficient free IP capacity; an input field does not
imply a separate subnet. Gateway and agent integration must remain separate
from each other and from every private endpoint subnet.

> [!IMPORTANT]
> **Confirm subnet suitability and authorized use through the platform process
> before deployment.** Existing does not automatically mean compatible or available.
>
> **Where to check:** in the Azure portal, open
> **Virtual networks > your VNet > Subnets > your subnet** for the address range,
> delegation and attached NSG, and the VNet's **Overview** for region/subscription.
> Use the [subnet and permission prerequisites](../../../docs/private-connectivity.md#existing-network-prerequisites)
> as the checklist. The platform owner must also confirm free IP capacity,
> existing service bindings/reservations, routing, firewall/NSG rules and private
> DNS resolution; these checks extend beyond the subnet pane.
>
> **A successful Terraform plan is not a full readiness or connectivity check.**

<a id="how-client-and-agents-fit"></a>

### Selected private components and DNS inputs

**In this `existing` scenario, Terraform creates none of these subnets.** The
platform must supply compatible existing subnets for the selected components.
**Private Blob connectivity, private Hosted Agent infrastructure and the new
test VM are all selected here**, so their required inputs are included in
the complete network object above:

| Selected feature | Required fields inside `existing_private_network` | Placement in this example |
| --- | --- | --- |
| Private Blob connectivity | `endpoint_subnet_ids.storage`, `private_dns_zone_ids.storage` | Blob endpoint in `snet-model-private-links`, using the central Blob zone. |
| Private Hosted Agent outbound integration | `agent_subnet_id` | Separate `snet-agents-outbound` integration subnet, delegated to `Microsoft.App/environments`. |
| Private Hosted Agent and registry endpoints | `endpoint_subnet_ids.agents`, `endpoint_subnet_ids.registry`, `private_dns_zone_ids.registry` | Both endpoints share `snet-model-private-links`; registry uses the central ACR zone. |
| New private test VM | `client_subnet_id` | `snet-test-clients`, not automatically the production application's subnet. |

**The test VM is a test computer, not an intermediary for application traffic.**
From it, you can check private DNS resolution, gateway reachability and an
authenticated model call through the gateway. A production application is also
a gateway client, but it can remain in its own existing network if routing,
private DNS resolution and authentication are in place. It does not have to run
in the sample's `client` subnet or send requests through the test VM.
An approved existing private client can be used instead of creating this
additional, billable VM in a different selection; in that case, leave the
test-VM feature off and omit `client_subnet_id` before deploying a new workload.
This walkthrough explicitly selects the new VM.

For private Hosted Agents, the supplied integration subnet must be separate from
gateway integration and all private endpoint subnets. Supplying `agent_subnet_id`
alone is not the complete feature configuration: the required agent/registry
endpoint and DNS inputs must also be agreed; all are included above. Existing
mode never creates a missing agent subnet automatically.

### Background only: the core profile and create-network comparison

These other starting points explain the different counts; they do not change
the eight-field, five-subnet setup selected above.

The reusable existing-network profile has three **core subnet-ID fields**:
`gateway_subnet_id`, `endpoint_subnet_ids.gateway` and
`endpoint_subnet_ids.models`. A core-only setup can use two or three distinct
subnets, depending on approved sharing of gateway/model endpoint subnets.
Gateway integration must remain separate from those endpoints. That smaller
profile does not include the network inputs for all our selected components.

For comparison, when `enable_private_networking = true` and
`private_network_mode = "create"`, `private-network.tf` creates the three subnet
roles `gateway`, `endpoints` and `client`. Gateway/model private endpoints share
the created `endpoints` subnet. The `client` subnet is created even when the
optional test VM is not enabled. A fourth subnet, `agents`, is added only with
`enable_private_hosted_agent = true`; deploying an arbitrary agent does not
automatically enable this option. That create-mode count is not the subnet count
for this existing-network walkthrough.

## Access settings for this walkthrough

### Required values supplied by profiles

&#x1F535; **PROFILE** - leave these lines commented in the **base** file.
The existing-network input supplies ownership/IDs; the selected access profile
supplies the stage-specific private-access values.

```hcl
# private_network_mode                     = "existing"
# private_dns_zone_group_management        = "workload"
# enable_private_networking                = true
# gateway_private_endpoint_manual_approval = true
# gateway_public_network_access           = "Disabled"
# models_public_network_access            = "Disabled"
```

The disabled public-access values illustrate the **final** state selected by
[private-only](../../../01-04-profiles/private-only.tfvars.json), not the first-create
configuration. The
[private-connectivity](../../../01-04-profiles/private-connectivity.tfvars.json)
profile leaves gateway public access enabled and is only an intermediate stage.
The documented bootstrap can also require a separately approved temporary
Models-Public override.

Profiles are **not loaded automatically** merely because they exist in a folder.
Use the [input composition rules](../../../01-04-deployment.md#compose-the-inputs)
and the approved staged procedure; do not jump directly to the final profile.

<a id="optional-additions-left-off-in-this-example"></a>

### Required Entra caller access

**Application-to-gateway calls must use Entra ID in this walkthrough.** The
selected owner of the caller role assignments is this Terraform deployment.
This is a requirement of the chosen example, not an interchangeable optional
authentication choice.

&#x1F7E2; **ACTIVE** - this complete block is already active in the Scenario 01
base example. Keep one copy in the protected base inputs and replace the
fictional principal with an approved existing Entra identity:

```hcl
gateway_access_principals = {
  demo_application = {
    principal_id   = "22222222-3333-4444-8555-666666666666"
    principal_type = "ServicePrincipal"
  }
}
```

`demo_application` is a stable Terraform map label, not a new application.
`principal_id` must be the existing service principal or managed identity's
**object/principal ID** in the gateway subscription's tenant, not its client ID
or the app registration's object ID. `ServicePrincipal` also covers managed
identities. See [where to find the correct identity](../../../docs/reference.md#find-optional-principal-ids).

Terraform grants **AI Gateway Models User at gateway scope**, covering all its
models, not management or key retrieval. Confirm that scope and the deployment
identity's role-assignment permissions. If an equivalent grant is already
platform-managed, agree its ownership/import rather than creating a duplicate;
selecting Terraform in this example does not transfer existing IAM ownership.

> [!IMPORTANT]
> **A caller role assignment is not an authentication switch.** The application
> must actually acquire and send an Entra token using the
> [token and consent contract](../../../docs/reference.md#token-and-consent-contract).
> This block creates no application/identity, disables no API key and does not
> convert the existing test-VM or hosted-agent reference calls from keys to Entra.
> Their key-based success is not proof of this requirement. Verify the intended
> caller with the [Entra probe](../../../docs/reference.md#verify-the-selected-client)
> and its approved private route; that probe uses the signed-in Azure CLI identity,
> not automatically the `demo_application` entry.

### Selected private features

&#x1F7E2; **ACTIVE** - these features are part of this walkthrough, not left
off. These assignments are already active in the Scenario 01 base example;
keep one copy in the same protected base input file:

```hcl
storage_public_network_access   = "Disabled"
enable_storage_private_endpoint = true

enable_private_hosted_agent = true

enable_private_test_client         = true
private_test_client_ssh_public_key = "ssh-ed25519 <approved-public-SSH-key>"
```

| Selected component | Effect and remaining prerequisites |
| --- | --- |
| Private Blob connectivity | Disables Storage public-network access and adds the Blob private endpoint. Its subnet and central DNS zone are included above. Follow the [Blob connectivity checks](../../../docs/private-connectivity.md#optional-policy-restricted-blob-storage); this is not proof of hosted-agent access to Storage. |
| Private Hosted Agent infrastructure | Adds a separate VNet-injected Basic Foundry account/project and agent/registry endpoints; it does not convert the original account or deploy an agent application. Configure injection when the new account is created, verify its delegated subnet and region/capacity, and follow the [separate application and acceptance gates](../../../docs/private-hosted-agent.md#deployment-and-acceptance-gates). |
| New private test VM | Creates an additional billable VM without a public IP in the supplied client subnet. Replace the deliberately unusable SSH placeholder with an approved OpenSSH **public** key before validation/planning. Check VM quota, platform egress and the [test-client permissions](../../../docs/private-connectivity.md#test-client-permissions), including custom role-definition permissions; caller-role assignment rights alone do not cover them. |

The SSH key configures VM access; it is not the application's Entra identity or
a gateway API key. The test helper uses Run Command. Do not copy a private SSH
key into any input file.

**These selections are not a claim that every resource or traffic flow is
private-only.** The private-agent extension retains the original agent
account/project and does not change ACR's public-access setting. Agent
application deployment, its caller authentication and runtime identity remain
separate work. Review these boundaries in the
[private-agent reference](../../../docs/private-hosted-agent.md#resource-changes).
Storage, Premium ACR and monitoring are already core supporting resources;
the selected flags do not replace their scope, cost or access review.

### Settings that do not belong to this scenario

&#x1F534; **NOT THIS SCENARIO** - do not activate these create-network settings.

```hcl
# private_network_mode           = "create"
# private_network_address_prefix = "10.247.0.0/16"
```

Do not set `existing_private_network = null` for the existing-network case.
Do not import platform networks, central zones, links or the resolver into the
new workload state.

## Use this reference alongside the runbook

Use the Scenario 01 base example and the complete network object above as
references for the protected working inputs, or keep the complete approved files
supplied by your organization. Never overwrite an existing approved input file
with fictional examples. Replace the illustrative values and agree the
network/DNS contract, policy, permissions, regions, quota and selected feature scope
before planning. Keep real inputs and state out of public Git.

Continue with the [scenario prerequisites](../../../docs/scenarios/01-existing-network.md#before-you-start)
and the [shared runbook order](../../../01-04-deployment.md#runbook-order).
This reference does not approve temporary public access, an apply, RBAC changes
or platform changes, and it does not promise private-from-first-create behavior.
