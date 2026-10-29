# Scenario 01: filled input reference for existing networking

[Back to Scenario 01](../../../docs/scenarios/01-existing-network.md)

Use this reference to understand how the inputs fit together when the **gateway
workload is new**, but networking and central Private DNS already belong to the
platform team. The intended end state is private gateway/model access after the
approved deployment stages.

> [!CAUTION]
> Subscription/object IDs, resource names, contacts and capacity values below are
> fictional. This is a reading aid, not approved deployment input or a separate
> deployment procedure. Do not pass this Markdown file to Terraform.

## Color key

The labels carry the meaning even when colors are unavailable.

| Marker | What to do |
| --- | --- |
| &#x1F7E2; **ACTIVE** | The base assignment already has no `#`. Replace the illustrative value; leave explanatory comments alone. |
| &#x1F535; **PROFILE** | Set the value through the selected network or access input file, not through a duplicate assignment in the base file. |
| &#x1F7E1; **OPTIONAL - OFF** | Leave the setting commented out for this example. Enable only after agreeing the need, prerequisites and scope. |
| &#x1F534; **NOT THIS SCENARIO** | Do not activate settings that create a parallel network/DNS foundation. |

In HCL, `#` starts a comment. **Never remove every `#`**: explanation text must
remain commented. When deliberately enabling an optional object, uncomment and
fill the entire block, including its closing brace.

## Filled base inputs

&#x1F7E2; **ACTIVE** - these are the assignment lines in the base input file.
Use the
[Base template (`01-04-terraform.tfvars.example`)](../../../01-04-terraform.tfvars.example)
as the editable starting point if no approved workload input file exists.

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

**The base inputs alone enable neither existing-network ownership nor private
access.** The next input file and the approved stage-specific access settings
are also required.

## Filled existing-network inputs

&#x1F535; **PROFILE** - this illustrates the contents of the protected
environment copy of
[01-04-profiles/network-existing.tfvars.json](../../../01-04-profiles/network-existing.tfvars.json).
JSON has no `#` comments: every entry below is an assignment when that file is
explicitly selected.

```json
{
  "private_network_mode": "existing",
  "private_dns_zone_group_management": "workload",
  "existing_private_network": {
    "gateway_subnet_id": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-network/providers/Microsoft.Network/virtualNetworks/vnet-demo-gateway/subnets/snet-gateway-outbound",
    "endpoint_subnet_ids": {
      "gateway": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-network/providers/Microsoft.Network/virtualNetworks/vnet-demo-gateway/subnets/snet-gateway-private-links",
      "models": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-network/providers/Microsoft.Network/virtualNetworks/vnet-demo-models/subnets/snet-model-private-links"
    },
    "private_dns_zone_ids": {
      "gateway": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-dns/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net",
      "cognitiveservices": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-dns/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com",
      "openai": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-dns/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com",
      "services": "/subscriptions/11111111-2222-4333-8444-555555555555/resourceGroups/rg-demo-dns/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com"
    }
  }
}
```

All shown resource IDs refer to **fictional existing platform resources**, not
resources this example asks Terraform to create. Obtain the actual IDs and
readiness confirmation from the platform owner using the
[field-by-field mapping and Portal lookup](../../../01-04-deployment.md#find-resource-ids-and-fill-in-the-network-input-file).
DNS zone IDs are not Private DNS Resolver IDs.

| Example choice | What must be agreed or verified |
| --- | --- |
| Three base subnet fields | These represent three roles, not necessarily three distinct subnets; see the breakdown below. Existing does not mean available or compatible. |
| Subscription in subnet IDs | The example uses the same fictional subscription as the base file. The sample requires endpoint subnets in the workload subscription. |
| Four central DNS zones | The names are real technical zone names; their subscription/group IDs must be replaced. Central zones may be in another subscription with the required permissions. Four zones do not mean four private endpoints. |
| `"private_dns_zone_group_management": "workload"` | This is an illustrative ownership choice, not a customer decision. Use `workload` only when the workload may create endpoint-to-zone associations; use `platform` when platform automation owns them. Neither transfers ownership of central zones, VNet links or the resolver. |

The network file chooses **ownership**, not an access stage. Keep the complete
`existing_private_network` object: a later assignment replaces the whole object,
not just its changed fields.

### Three input fields, two or three actual subnets

The two entries named `gateway` and `models` inside `endpoint_subnet_ids` are
**not the complete set of subnet inputs**. There is also `gateway_subnet_id`.
All three fields below belong to `existing_private_network`:

| Field | Purpose | Subnet in the filled example |
| --- | --- | --- |
| `gateway_subnet_id` | Gateway outbound VNet integration, used to reach private backends. | `snet-gateway-outbound` |
| `endpoint_subnet_ids.gateway` | Gateway private endpoint: the private entry point used by callers. | `snet-gateway-private-links` |
| `endpoint_subnet_ids.models` | Model-service private endpoint, reached by the gateway. | `snet-model-private-links` |

This example deliberately shows **three distinct subnets**. The gateway and
model endpoint fields may instead contain the **same suitable, platform-approved
subnet ID**. The basic setup then uses **two distinct subnets but still three
input fields**. Gateway integration must remain separate from every private
endpoint subnet.

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

### How `client` and `agents` fit

When `enable_private_networking = true` and `private_network_mode = "create"`,
`private-network.tf` creates the three subnet roles `gateway`, `endpoints` and
`client`. Gateway/model private endpoints share the created `endpoints` subnet.
The `client` subnet is created even when the optional test VM is not enabled.
A fourth subnet, `agents`, is added only with
`enable_private_hosted_agent = true`; deploying an arbitrary agent does not
automatically enable this option.

**In this `existing` scenario, Terraform creates none of these subnets.** The
platform must supply compatible existing subnets for any enabled additions.
Neither optional feature below is enabled in the filled example:

| Optional feature | Additional field inside `existing_private_network` | Purpose |
| --- | --- | --- |
| `enable_private_test_client = true` | `client_subnet_id` | Subnet for the sample's optional private test VM, not automatically the production application's subnet. |
| `enable_private_hosted_agent = true` | `agent_subnet_id` | Separate integration subnet for private Hosted Agents; required endpoint/DNS inputs must also be supplied. |

**The test VM is a test computer, not an intermediary for application traffic.**
From it, you can check private DNS resolution, gateway reachability and an
authenticated model call through the gateway. A production application is also
a gateway client, but it can remain in its own existing network if routing,
private DNS resolution and authentication are in place. It does not have to run
in the sample's `client` subnet or send requests through the test VM.
An approved existing private client can be used instead of creating this
additional, billable VM; in that case, leave the test-VM feature off and omit
`client_subnet_id`.

For private Hosted Agents, the supplied integration subnet must be separate from
gateway integration and all private endpoint subnets. Supplying `agent_subnet_id`
alone is not the complete feature configuration: the required agent/registry
endpoint and DNS inputs must also be agreed. Existing mode never creates a
missing agent subnet automatically, and its total subnet count is **not always
four**; it depends on the enabled features and approved endpoint-subnet sharing.

## Which commented settings stay commented?

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

### Optional additions left off in this example

&#x1F7E1; **OPTIONAL - OFF** - all assignment lines below remain commented.

```hcl
# gateway_access_principals = {
#   demo_application = {
#     principal_id   = "22222222-3333-4444-8555-666666666666"
#     principal_type = "ServicePrincipal"
#   }
# }

# storage_public_network_access   = "Disabled"
# enable_storage_private_endpoint = true

# enable_private_hosted_agent = true

# enable_private_test_client         = true
# private_test_client_ssh_public_key = "ssh-ed25519 <approved-public-SSH-key>"
```

| Optional block | Before enabling it |
| --- | --- |
| `gateway_access_principals` | Obtain approved Entra **object** IDs, not client/application IDs. The grant covers all gateway models and does not disable existing API keys. |
| Private Blob Storage | Agree the staged setup and add `endpoint_subnet_ids.storage` and `private_dns_zone_ids.storage` to the complete network object. Gateway/model private access alone does not make Storage private; leaving this block off retains the Storage public-network default. |
| Private hosted-agent extension | Agree the extra scope and agent/registry subnet and DNS inputs. It is not required for a basic model call through the gateway. |
| New private test VM | Agree cost/scope, supply `client_subnet_id` and an approved public SSH key. The shown key is deliberately not usable. An approved existing private client can be used instead. |

Leaving optional additions off **does not remove core supporting resources**:
the base module still includes the agent account/project, Storage, Premium ACR
and monitoring. Review their scope, access posture and costs separately.

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

Start from the linked editable templates, or keep the complete approved input
files supplied by your organization. Never overwrite an existing approved input
file with fictional examples. Replace the illustrative values and agree the
network/DNS contract, policy, permissions, regions, quota and optional scope
before planning. Keep real inputs and state out of public Git.

Continue with the [scenario prerequisites](../../../docs/scenarios/01-existing-network.md#before-you-start)
and the [shared runbook order](../../../01-04-deployment.md#runbook-order).
This reference does not approve temporary public access, an apply, RBAC changes
or platform changes, and it does not promise private-from-first-create behavior.
