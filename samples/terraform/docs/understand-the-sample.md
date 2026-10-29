# Understand the sample

[Overview and scenario selection](../README.md) | [Operator procedure](../01-04-deployment.md#start-here) | [Service architecture](architecture.md)

This is a **read-only explanation**, not a deployment procedure. Follow it on
GitHub without a terminal. Its example is a **new gateway workload using an
existing platform network and central DNS**:
[Scenario 01](scenarios/01-existing-network.md). If the gateway already exists,
retain its approved inputs, ownership mode and authoritative state; do not
create a second deployment.

By the end, you should be able to identify the input files, follow a subnet ID
into the configuration and explain which resources remain workload-owned.
No Terraform or Azure commands are needed for this walkthrough. Optional editor
help is separate from the explanation and does not authorize deployment.

**Looking for the selected filled example?** Open the
[Scenario 01 file checklist](scenarios/01-existing-network.md#files-for-this-scenario)
and [filled input walkthrough](../examples/filled/01-existing-network/README.md).
They include the active base example and complete inputs for API-key clients,
private Blob connectivity, private agents and the test VM. The generic
core-template explanations below are background, not that variant's full checklist.

## One configuration, not a sequence of scripts

Terraform reads the `.tf` files in `samples\terraform` **together as one root
configuration**. `main.tf` is not a script to run first, and
`private-network.tf` or `private-endpoints.tf` is not a script to run afterward.
Resource references and dependencies determine ordering, not filenames.
The file separation does not create modules, independent deployments or new
states. Files under `01-04-profiles` supply input values when selected; their presence
in a subfolder does not make Terraform execute or automatically load them.

| Term in the files | Meaning |
| --- | --- |
| `variable` / `var.` | An input's definition / its effective value, such as the chosen network mode. |
| `locals` / `local.` | Calculated helper values, such as which subnet ID to use. A list or calculation does not itself create resources. |
| `resource "azapi_resource"` | An Azure resource managed through Terraform's AzAPI provider. |
| `data "azapi_resource"` | A lookup of an existing Azure resource, not an import into this workload's ownership. |
| `count = 0` | No instance of that resource is managed by this configuration. |
| `for_each = {}` | The collection is empty, so no resource instances are managed for that block. |

On a **new** workload, these empty selections suppress creation. Changing an
already-deployed selection to empty can propose removal of previously managed
resources instead; it is not a safe ownership-migration mechanism.

## Which files do I open or edit?

Start with the input sources for your selected variant. The implementation
files below are for the later [input-to-code explanation](#follow-one-input-through-the-code),
not additional files to edit or run in sequence.

| File | Purpose | Normal environment-specific edit? |
| --- | --- | --- |
| [Filled Scenario 01 base example (`01-terraform.tfvars.example`)](../examples/filled/01-existing-network/01-terraform.tfvars.example) | Base/model values, an empty Entra caller map for API-key clients and selected private features already active together. No secret key value belongs in the file. | For that variant, use one protected working copy, replace fictional values and retain the [complete network inputs](../examples/filled/01-existing-network/README.md#filled-existing-network-inputs). Do not append duplicate blocks or overwrite approved inputs. |
| [Generic base template (`01-04-terraform.tfvars.example`)](../01-04-terraform.tfvars.example) | Alternative starting template for other feature selections. | For a **new** workload only, select this or the filled base example, not both. The [base-file step](../01-04-deployment.md#2-create-or-select-a-base-input-file) prepares the protected copy. |
| [01-04-profiles/network-existing.tfvars.json](../01-04-profiles/network-existing.tfvars.json) | Core-only template selecting `existing` and supplying subnet/zone IDs. | A protected copy needs all inputs for the selected features. The filled variant uses the larger [complete JSON block](../examples/filled/01-existing-network/README.md#filled-existing-network-inputs), not this core-only object unchanged. |
| [01-04-profiles/network-create.tfvars.json](../01-04-profiles/network-create.tfvars.json) | Selects sample-managed network/DNS ownership. | Select it for the approved scenario; it does not by itself enable private networking. |
| [01-04-profiles/private-connectivity.tfvars.json](../01-04-profiles/private-connectivity.tfvars.json) / [01-04-profiles/private-only.tfvars.json](../01-04-profiles/private-only.tfvars.json) | Intermediate and final private-access settings, independent of network ownership. | Select the correct shared file for the approved stage; do not customize the shared profile for one environment. |
| [variables.tf](../variables.tf) | Input types, defaults and validation rules. | Read to understand inputs; normally leave the definitions unchanged. |
| [private-network-context.tf](../private-network-context.tf) | Ownership switch, existing-resource lookups, checks and resolved subnet IDs. | Read; normally leave the implementation unchanged. |
| [private-network.tf](../private-network.tf) | Conditional sample-managed VNet, subnet, NSG, private DNS-zone and VNet-link creation. | Read; do not delete or comment out blocks to reuse networking. |
| [private-endpoints.tf](../private-endpoints.tf) | Workload private endpoints, gateway connection approval and endpoint DNS associations. | Read; these resources are still needed when the foundation is reused. |

An existing Terraform/Terragrunt pipeline can pass approved platform module
outputs through the [adapter](reference.md#optional-terragrunt-adapter) **instead
of** copying the network template. Keep one authoritative input/deployment process.

The other core files describe the workload: [main.tf](../main.tf) handles naming,
resource groups and shared monitoring; [ai-gateway.tf](../ai-gateway.tf) describes
the gateway and routing; [foundry-models.tf](../foundry-models.tf) describes the
model account/deployments; [foundry-agents.tf](../foundry-agents.tf) describes the
base agent account/project, Storage and Premium registry.

**Those agent and supporting resources are core sample resources.** The optional
private hosted-agent extension is additive: disabling it does not remove the
base account/project, Storage or registry. Terraform does not start an agent
application merely by creating its infrastructure. Approve the full sample's
resource scope and costs, not just the gateway. The gateway/model Private-only
profile does not make every supporting service private; see the
[base architecture and private boundaries](architecture.md#2-base-private-connectivity).

## Three core subnet inputs

The existing-network template has **three core subnet-ID fields**. Two are
entries in `endpoint_subnet_ids`; the third sits outside that map.
The [selected filled variant](../examples/filled/01-existing-network/README.md#filled-existing-network-inputs)
extends this to **eight subnet-ID fields and six DNS zones**; do not stop at
the three core fields when its private features are enabled.

| Create-mode subnet role | Field under `existing_private_network` | Job |
| --- | --- | --- |
| `gateway` | `gateway_subnet_id` | Dedicated outbound VNet integration: the gateway uses this subnet to reach private backends. |
| `endpoints` | `endpoint_subnet_ids.gateway` | Placement of the gateway's private ingress endpoint. |
| `endpoints` | `endpoint_subnet_ids.models` | Placement of the model account's private endpoint. |
| `client` | `client_subnet_id` | Required in existing mode only when the optional sample test VM, `enable_private_test_client`, is enabled. |
| `agents` | `agent_subnet_id` | Required for the optional private hosted-agent extension, which also needs additional endpoint/DNS inputs. |

**The two endpoint fields may contain the same full, approved subnet ID.**
Then the three core fields refer to two physical subnets: one for gateway
integration and one shared by the gateway/model private endpoints. The
integration subnet must remain separate from private endpoint subnets.
Separate endpoint subnets are also possible if the platform approves their
placement, routes and policies.

`gateway` and `models` inside the endpoint map are **role keys**, not required
Azure subnet names. The example VNet/subnet names are placeholders, not a
required VNet count or topology. Four DNS zone entries do not mean four subnets
or four private endpoints.

With private networking enabled, `create` always creates the three base subnet
roles `gateway`, `endpoints` and `client`, even if the sample VM is disabled.
It adds `agents` only for the private hosted-agent extension. In `existing`,
an unused sample VM does not require a client subnet. An existing corporate
private client does not need to become a Terraform-managed VM.

## Replacement checklist for existing-network inputs

This section explains the **generic core template** and shared base template.
For the selected filled variant, use its [base-value guidance](../examples/filled/01-existing-network/README.md#filled-base-inputs)
and [complete network mapping](../examples/filled/01-existing-network/README.md#filled-existing-network-inputs)
instead of treating the seven-ID checklist below as complete.

These **color symbols plus text labels belong to this guide**, not to the input
files. GitHub cannot persist arbitrary colored substring highlights in an actual
JSON file; its syntax colors do not identify placeholders. **Do not insert emoji,
Markdown, HTML or comments into JSON.**

When approved to prepare an environment copy of
[network-existing.tfvars.json](../01-04-profiles/network-existing.tfvars.json):

| Label | What it means here |
| --- | --- |
| 🟨 **REPLACE** | Replace each of the seven complete resource-ID values below, not just the zero UUID or the word `replace`. |
| 🟩 **KEEP FOR THIS MODE** | Keep `"private_network_mode": "existing"` for this network/DNS reuse scenario, not for every deployment. It does **not** mean the gateway already exists. |
| 🟦 **DECIDE WITH PLATFORM TEAM** | `private_dns_zone_group_management` is `"workload"` in the template, but is an ownership decision, not an always-keep value. Agree `"workload"` or `"platform"` for endpoint DNS associations; exactly one owner. |

Central ownership of a DNS zone does **not** automatically mean platform
ownership of its endpoint associations. See the
[DNS ownership explanation](#who-manages-dns-and-how-do-the-input-files-get-selected).
This file must be explicitly selected with the other inputs; by itself it
neither enables private networking nor ensures Private-only access.

**Seven-ID checklist:** all fields below are inside `existing_private_network`
in `network-existing.environment.tfvars.json`. Each row is 🟨 **REPLACE**.

| Field | Copy this complete approved resource ID |
| --- | --- |
| `gateway_subnet_id` | Dedicated gateway **outbound VNet integration** subnet ID. |
| `endpoint_subnet_ids.gateway` | Gateway **ingress Private Endpoint** subnet ID. |
| `endpoint_subnet_ids.models` | Model account's **Private Endpoint** subnet ID. |
| `private_dns_zone_ids.gateway` | Full zone ID ending in `/privateDnsZones/privatelink.azure-api.net`. |
| `private_dns_zone_ids.cognitiveservices` | Full zone ID ending in `/privateDnsZones/privatelink.cognitiveservices.azure.com`. |
| `private_dns_zone_ids.openai` | Full zone ID ending in `/privateDnsZones/privatelink.openai.azure.com`. |
| `private_dns_zone_ids.services` | Full zone ID ending in `/privateDnsZones/privatelink.services.ai.azure.com`. |

Each approved ID belongs **in full inside the existing quotes**, preserving JSON
keys, nesting, commas and braces. Dotted paths above describe nesting; do not
create dotted JSON keys. Resource-ID structure and the required DNS zone names
are not arbitrary replacements. The operator's
[resource-ID procedure](../01-04-deployment.md#find-resource-ids-and-fill-in-the-network-input-file)
explains how to obtain them. Do not globally replace subscription UUIDs:
central zones may use another subscription. Optional features need their
additional inputs.

When starting from the **shared base template**, 🟨 **REPLACE** the zero `subscription_id`
and `platform@example.com`. For the workload name, regions and model settings,
🟦 **DECIDE WITH PLATFORM TEAM**: `aigateway` is a valid naming default;
`eastus2` and the model settings are examples requiring approval, not automatic
recommendations. The operator uses the
[required-values table](../01-04-deployment.md#3-fill-in-the-required-values).

## Follow one input through the code

Read these steps; do not execute or duplicate the source snippet.

1. The selected environment copy of the existing-network profile supplies
   `private_network_mode = "existing"` and `existing_private_network`.
   [variables.tf](../variables.tf) declares and validates those inputs.
   The private-access profile separately enables private networking;
   ownership alone does not enable it or select Private-only.
2. [private-network-context.tf](../private-network-context.tf) evaluates this
   existing expression inside its `locals` block:

   ```hcl
   create_private_network = var.enable_private_networking && var.private_network_mode == "create"
   ```

   With private networking enabled and mode `existing`, the result is `false`.
   Existing subnet/VNet metadata is read through data lookups, and helper values
   select the supplied IDs.
3. In [private-network.tf](../private-network.tf), find `private_vnet` and
   `private_subnets`. The VNet's conditional count becomes `0`; the subnet
   resource collection becomes `{}`. Creation of the sample NSGs, DNS zones
   and VNet links is also guarded by `create_private_network`.
4. Follow `existing_private_network.gateway_subnet_id` to
   `local.private_gateway_subnet_id`, then to `subnetResourceId` in
   [ai-gateway.tf](../ai-gateway.tf). That is the existing subnet used for gateway
   outbound integration.
5. In [private-endpoints.tf](../private-endpoints.tf), find
   `resource "azapi_resource" "private_endpoint"`. These workload endpoints
   remain enabled and use the resolved `endpoint_subnet_ids` for placement.
   They are **new endpoints in approved existing subnets**.

**Existing mode reuses the foundation; it does not disable workload networking.**
All root files remain loaded. Missing required inputs fail; they do not trigger
a fallback network creation.

## Who manages DNS, and how do the input files get selected?

In existing mode, central DNS zones, resolver, links, routing and firewall remain
with the platform. **Zone ownership is separate from endpoint association
ownership.** `private_dns_zone_group_management = "workload"` means Terraform
manages the new endpoints' associations to existing zones, not new central zones.
`"platform"` leaves those associations to platform policy/automation. Choose
exactly one owner, confirm permissions and wait for actual DNS readiness.
Do not select `"platform"` merely because the zones are centrally owned.

For a new workload, real base values go in `terraform.tfvars` (or the approved
alternative) and network IDs go in the selected environment network file.
Terraform automatically reads the standard `terraform.tfvars` and automatic
var-files; arbitrary filenames and shared profiles require explicit selection.
An alternative such as `workload.tfvars` is not automatically read just because
it exists. The [input composition step](../01-04-deployment.md#compose-the-inputs)
supplies the `-var-file` arguments in the approved order.

Later input values override earlier ones **for the whole variable**;
Terraform does not automatically deep-merge nested objects across var-files.
Keep the complete `existing_private_network` object in its responsible input
source instead of splitting partial versions across files. Keep the complete
approved file selection on monitoring, update and drift plans too.

## Where do I edit, and where does Terraform run?

An **editor**, such as VS Code, is where you read and edit files. A
**terminal or CI runner** executes the Terraform CLI from `samples\terraform`
in the approved checkout, or with its working directory explicitly pointing
there. VS Code's integrated **PowerShell 7** terminal is one possible **local**
command environment, not a requirement.

Enterprise platform teams often use an approved CI runner with the workload's
existing state/backend, complete inputs and credentials. Retain that authoritative
process; do not start a second state in Cloud Shell or on another machine.
Confirm [Inputs and state](../01-04-deployment.md#inputs-and-state) before initialization
or planning.

| File type | Language and purpose |
| --- | --- |
| `.tf` | HCL (HashiCorp Configuration Language): Terraform resource and configuration definitions. |
| `.tfvars` | HCL: environment input values, not a script to execute. |
| `.tfvars.json` | JSON: environment input values, not a script to execute. |
| `.ps1` | PowerShell: helper scripts, used only at their documented step. |

## Optional: highlight input placeholders in VS Code

The optional [terraform-inputs.code-workspace](../terraform-inputs.code-workspace)
provides editor markings with **Highlight 2.1.0**
([Marketplace](https://marketplace.visualstudio.com/items?itemName=fabiospampinato.vscode-highlight),
[source](https://github.com/fabiospampinato/vscode-highlight)).
Use this third-party extension only if approved by your organization.
The workspace **recommends but does not install** it.

For a clean first-time setup, keep this order:

1. In your approved **VS Code or VS Code Insiders**, open **File > Preferences >
   Profiles**, then **New Profile**. Choose **Empty Profile**, create a separate
   profile such as `Terraform Inputs`, and use it for the current window.
2. **Before installing Highlight**, use **File > Open Workspace from File** to
   load the checked-out `samples\terraform\terraform-inputs.code-workspace`.
   Merely opening its JSON as text does **not** activate it. Confirm the new
   profile is still active. The workspace opens `.` relative to itself
   (`samples\terraform`); it already sets nonempty `highlight.regexes` and
   `highlight.enabled` to `true` at **Workspace** scope.
3. **Only now**, open **Extensions** (**Ctrl+Shift+X**), search
   `@id:fabiospampinato.vscode-highlight`, right-click **Highlight**, choose
   **Install Another Version**, and select **2.1.0** in this profile.
   Do not choose **Apply Extension to all Profiles**. Open
   `01-04-terraform.tfvars.example` or your selected input copy to see the markings.

**Why this order:** in 2.1.0, first activation with empty `highlight.regexes`
writes default TODO rules to global/user settings. Highlight's own
**Enable/Disable/Toggle** commands write global settings too; do not use them.
The new profile and preloaded rules avoid disturbing existing profiles.
To turn markings off, open **Settings > Workspace** and set
`highlight.enabled` to `false`, not a User/global setting.

- **Appearance:** theme-native badge foreground/background, a warning border
  and bold text—not necessarily the GitHub legend's yellow/green/blue.
- **Marked fragments only:** the zero UUID, literal template example/replace
  resource names, `platform@example.com` and documented angle-bracket IDs inside
  quoted input values. Still replace the **complete approved resource ID**;
  do not reconstruct it from highlighted pieces.
- **Limits:** fixed DNS suffixes, keys, runtime `.tf` files and ordinary defaults
  are not highlighted. **Unmarked does not mean valid, approved or complete.**
  Matching is limited to input files under a `samples\terraform` path; a file
  from another checkout opened manually in that window may also match. Custom
  inputs elsewhere are not covered. The filled Scenario 01 example file and
  its non-zero fictional values are not covered by this generic placeholder
  helper; use the [filled replacement guidance](../examples/filled/01-existing-network/README.md).

This workspace contains no tasks, Terraform commands or Azure changes.
Editor profiles do not replace the approved deployment process or select a
Terraform state/backend; retain the existing authoritative state and pipeline.

## Which commands and helper scripts matter?

You do not run every script in the repository. For this walkthrough, run none.
The actual commands and safety gates remain in the
[operator procedure](../01-04-deployment.md#runbook-order).

| Terraform command | What it does |
| --- | --- |
| `init` | Initializes providers and the selected backend. Confirm state ownership first; do not create or migrate a backend casually. |
| `plan` | Compares configuration, state and refreshed resource information. Proposes changes without applying them; still needs the correct Azure context, inputs and permissions. |
| `apply` | Executes approved changes and can create, modify or delete billable resources. Review the saved plan first. |

State records Terraform's resource-to-Azure mapping; the backend stores that
state. Reusing platform IDs does not require copying platform state, importing
its resources into this workload or creating a competing owner.

| Helper under `scripts` | When it is relevant / side effects |
| --- | --- |
| [Test-Offline.ps1](../scripts/Test-Offline.ps1) | Maintenance checks in a separate clean checkout, not a customer deployment entry point. Uses `init -backend=false`; may download providers and writes local initialization/test files. No Azure deployment, but not necessarily network-free or read-only. |
| [Get-GatewayMonitoring.ps1](../scripts/Get-GatewayMonitoring.ps1) | Reads ARM monitoring linkage after resources exist. Does not create or repair the exporter/destination; metadata is not runtime delivery proof. |
| [Test-ModelAliases.ps1](../scripts/Test-ModelAliases.ps1) | Sends billable model requests to compatible chat-completions aliases. Requires reachable endpoints and caller permissions. |
| [Test-PrivateGateway.ps1](../scripts/Test-PrivateGateway.ps1) | Uses Run Command on the optional sample VM. Not a wrapper for an arbitrary existing corporate client. |
| [Test-DeploymentAcceptance.ps1](../scripts/Test-DeploymentAcceptance.ps1) | Optional sample-VM acceptance runner. Requires its VM ID even for diagnostics; reads ARM, runs a full drift plan and writes local reports. With `-RunPrivateProbe`, starts the designated deallocated VM, runs billable probes through Run Command and deallocates it afterward. |
| [Test-CustomerAcceptance.ps1](../scripts/Test-CustomerAcceptance.ps1) | Compatibility entry point for that same runner, not another workflow. |
| [Complete-PortalAcceptance.ps1](../scripts/Complete-PortalAcceptance.ps1) | Validates a passing VM backend report and operator-recorded portal evidence, then writes a local report. Does not open or independently inspect the portal. |

Without a sample VM, use the
[existing-private-client/manual acceptance path](private-connectivity.md#test-from-an-existing-private-client);
do not add a VM to obtain a passing automated report. Supporting helpers such as
`private-path-probe.py` are called by their documented runner, not extra beginner
setup steps. The repository's top-level `cli`, `commands` and `skills` belong to
separate interfaces; their installers are not Terraform deployment steps.

## Stop before deployment

You can now identify the input files, trace an existing subnet ID and explain
which resources remain workload-owned. Before a real plan, the operator obtains
the [platform handoff](../01-04-deployment.md#platform-handoff-before-a-plan) and follows
the [selected scenario](../01-04-deployment.md#first-decide-what-already-exists).

For a new existing-mode workload, new workload resources and private endpoints
are expected; changes to the central VNet/subnet/NSG/zone/link foundation are not.
Endpoint DNS associations follow the chosen owner. Unexpected removals or
replacements require a stop and separate review.

Do not demonstrate `apply`, `destroy`, imports or state moves during a code
review. The final Private-only profile is not a private-from-first-create
shortcut. Keep the approved, bounded new-deployment stages and never reopen an
already-private resource.
