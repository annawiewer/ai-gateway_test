# Scenario 01: new gateway on existing private networking

[All scenarios](../../README.md#choose-your-scenario)

Use this entry when **the gateway workload is new**, but the platform team
already manages the network and central Private DNS. The target is private-only
gateway/model access after approved staged setup.

If the gateway is already deployed, use [Scenario 04: update an existing gateway](04-update-existing.md)
instead. Do not start a new state or replace its inputs with these examples.

## Before you start

- Agree who owns the new workload's backend/state. Existing network and DNS
  keep their current owners, deployment process and state.
- Obtain approved subnet/zone IDs, routing and DNS readiness, deployment
  permissions and a reachable private test client.
- Confirm policy and cost approval for the [full sample scope](../../README.md#what-gets-deployed),
  including supporting services and the temporary public access required by the
  documented new-deployment stages. This is not a private-from-first-create promise.

## Files for this scenario

Paths below are relative to `samples/terraform`; use your organization's
approved filenames and input storage if already defined.
The `01-04-` prefix marks shared material; select only the files and stages
listed for this scenario, not every file in the profile library.

| File | Action |
| --- | --- |
| [Base template (`01-04-terraform.tfvars.example`)](../../01-04-terraform.tfvars.example) | If no approved workload input file exists, copy to a protected file such as `terraform.tfvars`. Fill in subscription, workload/gateway regions, publisher contact, model deployments and other approved workload values. |
| [01-04-profiles/network-existing.tfvars.json](../../01-04-profiles/network-existing.tfvars.json) | Use the complete approved environment input file if one is already supplied. Otherwise copy the template to a protected file such as `network-existing.environment.tfvars.json`, replace all placeholder IDs and agree `private_dns_zone_group_management`. Keep the complete `existing_private_network` object. |
| [01-04-profiles/private-connectivity.tfvars.json](../../01-04-profiles/private-connectivity.tfvars.json) | Select only for the approved intermediate private setup stage; the gateway is still public in this profile. |
| [01-04-profiles/private-only.tfvars.json](../../01-04-profiles/private-only.tfvars.json) | Select for the final gateway/model private-only stage after approval and connectivity checks. |
| All root `*.tf` files | Use the shared implementation unchanged. Do not copy a subset into a new folder or import the platform network into workload state. |

The existing-network copy selects **ownership**, not private access.
The access profile selects a deployment stage, not network ownership. Follow
the [input composition rules](../../01-04-deployment.md#compose-the-inputs) and the
approved procedure for any temporary override. A later object assignment
replaces the whole object; it does not merge extra fields into an earlier one.
Never place environment values, secrets or state in public Git.

For an illustration of the completed inputs, see the
[Scenario 01 filled input reference](../../examples/filled/01-existing-network/README.md).
It includes fictional base and network values, a color key and guidance on
which commented settings to leave alone. It supplements this scenario and the
shared runbook; it is not a separate deployment procedure.

## What the platform team supplies

The core network contract has three subnet fields:

| Field inside `existing_private_network` | Purpose |
| --- | --- |
| `gateway_subnet_id` | Gateway outbound VNet integration |
| `endpoint_subnet_ids.gateway` | Gateway private endpoint |
| `endpoint_subnet_ids.models` | Model-account private endpoint |

The two endpoint fields may use the **same approved endpoint subnet**. The
integration subnet remains separate: three fields do not necessarily mean
three physical subnets.

Supply the IDs of the four existing central zones:
`privatelink.azure-api.net`, `privatelink.cognitiveservices.azure.com`,
`privatelink.openai.azure.com` and `privatelink.services.ai.azure.com`.
Four DNS zones do not mean four private endpoints.

Choose one owner for endpoint-to-zone associations: `workload` lets this
configuration create zone groups against the existing zones; `platform` leaves
those associations to platform automation. Both require approved zone IDs.
Neither transfers ownership of central zones, links or the resolver.

See the [field-by-field input mapping](../../01-04-deployment.md#find-resource-ids-and-fill-in-the-network-input-file)
for required metadata, Portal lookup and conditional inputs for agent, Storage
or test-VM extensions. Complete the
[platform handoff](../../01-04-deployment.md#platform-handoff-before-a-plan)
before a plan.

## Continue with the shared procedure

Follow the [shared runbook order](../../01-04-deployment.md#runbook-order), using
existing ownership and the approved private stages. The canonical
[private-connectivity procedure](../private-connectivity.md) includes endpoint
approval, private-route checks and final closure of public access.

Use either an approved existing private client or the optional sample VM for
the applicable [acceptance path](../acceptance.md). The
[sample-VM runner](../end-to-end.md) is not required for an existing client.

**Stop** if state or platform ownership is unclear, IDs/permissions are missing,
DNS/routing is not ready, required temporary public access is prohibited, or a
plan proposes unapproved foundation resources, deletion or replacement. Do not
bypass policy or create parallel network/DNS resources to make the sample fit.
