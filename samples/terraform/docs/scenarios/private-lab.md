# New private lab with sample-managed networking

[All scenarios](../../README.md#choose-your-scenario)

Use this entry for **a new gateway workload and a new private test network**
owned by this sample. The target is private-only gateway/model access after
approved staged setup.

If central network and DNS already exist, use
[existing platform networking](existing-network.md). If the gateway already
exists, use [the update entry](update-existing.md).

## Before you start

- Agree the workload backend/state and ownership of the sample-managed network.
- Approve non-overlapping address ranges, regions, model quota and deployment
  permissions. This sample creates a gateway network, not a corporate hub,
  firewall, landing zone or central DNS resolver.
- Approve the [full sample footprint](../../README.md#what-gets-deployed), costs
  and applicable policies, including the temporary public access in the
  documented new-private-deployment procedure.
- Choose a suitable private client or the optional sample VM for acceptance.
  If the private hosted-agent extension is required, review its
  [creation-time requirements](../private-hosted-agent.md) before deployment.

## Files for this scenario

Paths are relative to `samples/terraform`.

| File | Action |
| --- | --- |
| [terraform.tfvars.example](../../terraform.tfvars.example) | For a new workload without approved inputs, copy to a protected file such as `terraform.tfvars`. Set workload values and approved network ranges; review any optional extensions. |
| [profiles/network-create.tfvars.json](../../profiles/network-create.tfvars.json) | Select as the ownership profile. It permits sample-managed foundation creation when private networking is enabled; it does not enable private networking on its own. |
| [profiles/private-connectivity.tfvars.json](../../profiles/private-connectivity.tfvars.json) | Select only for the approved intermediate private setup stage; this is not the final private-only state. |
| [profiles/private-only.tfvars.json](../../profiles/private-only.tfvars.json) | Select for final gateway/model private-only access after endpoint approval and private-route verification. |
| All root `*.tf` files | Leave the shared implementation in place; there is no separate lab stack to copy or assemble. |

Do not also load an existing-network profile or retain conflicting
`existing_private_network` values. Follow the
[complete input selection rules](../../deployment.md#compose-the-inputs);
profiles are not automatically active because they are in the folder.
Store environment-specific values outside public Git.

## What changes in this scenario

With private networking enabled, [private-network.tf](../../private-network.tf)
creates the sample's foundation: VNet, subnets, NSGs, DNS zones and links.
[private-endpoints.tf](../../private-endpoints.tf) supplies workload endpoints
and their DNS associations. Both files remain part of the same Terraform root.

The sample test VM is opt-in; its absence does not remove all client-network
foundation resources. Base agent, Storage and Registry resources remain part
of the stack. Private-only is not a blanket private-access setting for those
supporting services.

## Continue with the shared procedure

Follow the [shared runbook order](../../deployment.md#runbook-order) and the
canonical [private-connectivity procedure](../private-connectivity.md).
Any initial Models-Public override belongs only to the explicitly approved
new-deployment stage; do not infer private-from-first-create support.

Complete [acceptance](../acceptance.md) from the intended private client.
Use the [sample-VM runner](../end-to-end.md) only if that is your chosen client.

**Stop** if address ranges overlap, ownership or permissions are unresolved,
costs/policies are not approved, temporary public access is prohibited, or
private DNS/routing cannot be verified. Do not switch a previously deployed
sample-managed network to `existing` as a shortcut; that requires a separate
ownership/state migration review.
