# Scenario 01: new gateway on existing private networking

[All scenarios](../../README.md#choose-your-scenario) | [Filled walkthrough](../../examples/filled/01-existing-network/README.md) | [Shared procedure](../../01-04-deployment.md#runbook-order)

Use this entry when **the gateway workload is new**, but the platform team
already manages the network and central Private DNS. The target is private-only
gateway/model access after approved staged setup.

If the gateway is already deployed, use [Scenario 04: update an existing gateway](04-update-existing.md)
instead. Do not start a new state or replace its inputs with these examples.

**New to Terraform?** The [read-only explanation](../understand-the-sample.md)
explains file roles without running commands. To prepare the selected example,
use the file checklist below and its linked walkthrough; do not read every
implementation file first.

## Before you start

- Agree who owns the new workload's backend/state. Existing network and DNS
  keep their current owners, deployment process and state.
- Obtain approved subnet/zone IDs, routing and DNS readiness, deployment
  permissions and a reachable private test client.
- Agree the [gateway API-key handling](../../examples/filled/01-existing-network/README.md#api-key-client-authentication)
  for the filled variant: owner, scope, secret storage, delivery and rotation.
  The application needs no Entra caller grant for its key-authenticated gateway calls.
- Confirm policy and cost approval for the [full sample scope](../../README.md#what-gets-deployed),
  including supporting services and the temporary public access required by the
  documented new-deployment stages. This is not a private-from-first-create promise.

## Files for this scenario

Paths below are relative to `samples/terraform`; use your organization's
approved filenames and input storage if already defined.
The `01-04-` prefix marks shared material; select only the files and stages
listed for this scenario, not every file in the profile library.

The table follows the [filled variant](../../examples/filled/01-existing-network/README.md):
API-key client authentication, private Blob connectivity, private Hosted Agent
infrastructure and a new private test VM. Approve that scope before using it.
If complete approved workload/network files already exist, retain them instead
of copying either template.

| File or input section | Action for the filled variant |
| --- | --- |
| [Active base example (`01-terraform.tfvars.example`)](../../examples/filled/01-existing-network/01-terraform.tfvars.example) | Source for a protected working copy such as `terraform.tfvars`. Base/model values, an empty Entra caller map for API-key clients and the selected private features are already active in one file. Replace fictional values and the SSH public-key placeholder; do not add a secret API key or append those blocks again. |
| [Complete existing-network JSON](../../examples/filled/01-existing-network/README.md#filled-existing-network-inputs) | The JSON block, not the Markdown page, is the reference for `network-existing.environment.tfvars.json`. It includes all eight subnet-ID fields and six zone IDs for the selected features. Replace every fictional ID and agree `private_dns_zone_group_management`; keep the whole object in one input source. |
| [01-04-profiles/private-connectivity.tfvars.json](../../01-04-profiles/private-connectivity.tfvars.json) | Select only for the approved intermediate private setup stage; the gateway is still public in this profile. |
| [01-04-profiles/private-only.tfvars.json](../../01-04-profiles/private-only.tfvars.json) | Select for the final gateway/model private-only stage after approval and connectivity checks. |
| All root `*.tf` files | Use the shared implementation unchanged. Do not copy a subset into a new folder or import the platform network into workload state. |

**Different approved feature selection?** The
[generic base template](../../01-04-terraform.tfvars.example) and
[core-only network template](../../01-04-profiles/network-existing.tfvars.json)
remain starting points for other Scenario 01 variants. They are alternatives,
not additional files to layer over the filled example. Add every input required
by your selected features; the core network template is not the complete
network input for the filled variant.

The existing-network copy selects **ownership**, not private access.
The access profile selects a deployment stage, not network ownership. Follow
the [input composition rules](../../01-04-deployment.md#compose-the-inputs) and the
approved procedure for any temporary override. A later object assignment
replaces the whole object; it does not merge extra fields into an earlier one.
Never place environment values, secrets or state in public Git.

The [filled walkthrough](../../examples/filled/01-existing-network/README.md)
explains these values and remaining comments. The
[base-file selection step](../../01-04-deployment.md#2-create-or-select-a-base-input-file)
shows how to select one source without overwriting approved inputs.
Neither an example file nor its reference page is a separate deployment procedure.

## What the platform team supplies

For the filled variant, obtain the
[complete subnet and DNS mapping](../../examples/filled/01-existing-network/README.md#filled-existing-network-inputs):
**eight subnet-ID fields, five distinct existing subnets and six central zones**
in this illustration. The platform must approve actual placement and suitability;
the example's sharing choices are not a requirement on your topology.

<details>
<summary>Core-only network contract for other feature selections</summary>

The minimal gateway/model contract has three subnet fields. It is background,
not the full input checklist for the selected filled variant.

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

</details>

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
