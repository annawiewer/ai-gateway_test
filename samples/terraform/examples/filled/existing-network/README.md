# Filled input reference: new gateway on existing networking

[Back to the scenario](../../../docs/scenarios/existing-network.md)

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
Use [the base template](../../../terraform.tfvars.example) as the editable
starting point if no approved workload input file exists.

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

The model identifiers are real technical identifiers taken from the base
template, **not a fresh availability or quota confirmation**. `sku_name` is the
model deployment SKU; it does not change the sample's gateway SKU.
`GlobalStandard` does not guarantee processing only in Sweden.
`capacity` is model-deployment capacity, not a price or the gateway caller limit;
`token_limit` is a separate gateway token limit.

**The base inputs alone enable neither existing-network ownership nor private
access.** The next input file and the approved stage-specific access settings
are also required.

## Filled existing-network inputs

&#x1F535; **PROFILE** - this illustrates the contents of the protected
environment copy of
[profiles/network-existing.tfvars.json](../../../profiles/network-existing.tfvars.json).
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
[field-by-field mapping and Portal lookup](../../../deployment.md#find-resource-ids-and-fill-in-the-network-input-file).
DNS zone IDs are not Private DNS Resolver IDs.

| Example choice | What must be agreed or verified |
| --- | --- |
| Three subnet fields | Outbound integration is separate from private endpoints. The gateway/model endpoint fields may share one approved endpoint subnet; this illustration uses two. Existing does not mean available or compatible. |
| Subscription in subnet IDs | The example uses the same fictional subscription as the base file. The sample requires endpoint subnets in the workload subscription. |
| Four central DNS zones | The names are real technical zone names; their subscription/group IDs must be replaced. Central zones may be in another subscription with the required permissions. Four zones do not mean four private endpoints. |
| `"private_dns_zone_group_management": "workload"` | This is an illustrative ownership choice, not a customer decision. Use `workload` only when the workload may create endpoint-to-zone associations; use `platform` when platform automation owns them. Neither transfers ownership of central zones, VNet links or the resolver. |

The network file chooses **ownership**, not an access stage. Keep the complete
`existing_private_network` object: a later assignment replaces the whole object,
not just its changed fields.

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
[private-only](../../../profiles/private-only.tfvars.json), not the first-create
configuration. The
[private-connectivity](../../../profiles/private-connectivity.tfvars.json)
profile leaves gateway public access enabled and is only an intermediate stage.
The documented bootstrap can also require a separately approved temporary
Models-Public override.

Profiles are **not loaded automatically** merely because they exist in a folder.
Use the [input composition rules](../../../deployment.md#compose-the-inputs)
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

Continue with the [scenario prerequisites](../../../docs/scenarios/existing-network.md#before-you-start)
and the [shared runbook order](../../../deployment.md#runbook-order).
This reference does not approve temporary public access, an apply, RBAC changes
or platform changes, and it does not promise private-from-first-create behavior.
