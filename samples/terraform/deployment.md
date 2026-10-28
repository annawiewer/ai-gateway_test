# Deployment guide

[Overview and architecture](README.md)

## Start here

This is the **shared operator procedure** for the
[four deployment scenarios](README.md). Select the starting situation
below, prepare the approved inputs, then follow only the applicable procedure.
Specialist guides are linked at their execution step, not extra deployments to
run afterward.

**Not deploying yet?** Read [Understand the sample](docs/understand-the-sample.md)
without a terminal. File roles, the subnet-input explanation and optional editor
help live there; service behavior is explained in [Architecture](docs/architecture.md).

**Who:** the person operating the workload's approved deployment process, with
the network/DNS owner available for the handoffs below.
**Where:** the commands shown use PowerShell **7**, with the approved checkout's
`samples\terraform` as the working directory. Use the approved local terminal or
pipeline; Azure Portal and editor steps are labeled separately.

> [!IMPORTANT]
> This time-limited preview sample retains
> `Microsoft.ApiManagement/service@2025-09-01-preview` and SKU `AIGateway`.
> Microsoft requires migration **before January 15, 2027**. As checked
> October 25, 2026, the replacement `Microsoft.ApiManagement/aigateways`
> resource does not support gateway private endpoints. This guide does not
> upgrade the SKU/provider or perform that migration. Check
> [resource compatibility and lifecycle](docs/reference.md#resource-type-and-lifecycle)
> before deployment.

### First decide what already exists

| Starting situation | Ownership and access | Workload state and next action |
| --- | --- | --- |
| [New gateway on an existing private platform](docs/scenarios/existing-network.md) | `existing` plus the approved private-access stage | Use approved subnet/zone IDs and the backend for the **new gateway workload**, not the network team's state. Follow the [runbook order](#runbook-order). |
| [New private lab with sample-managed networking](docs/scenarios/private-lab.md) | `create` plus the approved private-access stage | Confirm a new workload backend and non-overlapping address range. The sample creates a network foundation, not a corporate landing zone. Follow the [runbook order](#runbook-order). |
| [Deliberate new public lab](docs/scenarios/public-lab.md) | `create`, without a private-access profile | Obtain explicit public-access and cost approval. Ownership alone does not activate private networking. Follow the [runbook order](#runbook-order). |
| [Update an existing gateway](docs/scenarios/update-existing.md) | Retain its approved ownership, access and exceptions | Keep complete inputs and authoritative state/backend. Use [Update an existing gateway](#update-an-existing-gateway), not new-deployment bootstrap. |

An **existing network** is not the same as an **existing gateway deployment**.
If you do not know which row applies, stop and ask the platform/deployment owner.
The sample creates its own workload resource group; it does not automatically
adopt an existing group, private endpoint, Foundry account or model deployment.

Also decide the final access posture: **Private-only** or intentionally
**Public**. Public is the configuration default, not the recommended fallback
when a private step fails. A new private deployment uses the explicitly
approved temporary-public stages described below. If even temporary public
access is prohibited, **stop before deployment**: this guide does not establish
a private-from-first-create procedure. An already-private deployment never
repeats those stages.

### Existing-network integration at a glance

For a **new gateway workload using centrally managed network and DNS**, prepare
the following inputs and owner confirmations. This is a map to the detailed
steps, not a second runbook or permission to skip their checks.

| Prepare | Who supplies it | File or next step |
| --- | --- | --- |
| Approved source, workload subscription/tenant, naming, regions, model choices and workload state/backend | Workload owner, with the model/platform owners | Use the [approved checkout](#2-open-the-approved-source-revision). Keep base inputs in `terraform.tfvars` or the already-approved input file; follow [Inputs and state](#inputs-and-state). |
| Integration subnet, gateway/model endpoint subnets and the four core private DNS zones | Network/DNS team, through its existing provisioning process | Fill **`network-existing.environment.tfvars.json`**, copied from the shared [existing-network template](profiles/network-existing.tfvars.json), using the [field-by-field ID guide](#find-resource-ids-and-fill-in-the-network-input-file). |
| One owner for endpoint DNS associations, plus permissions, routing, access-policy and test-client approval | Platform and workload owners together | Complete the [ownership and approval table](#platform-handoff-before-a-plan), then follow the [runbook order](#runbook-order), including the approved access path. |

The filenames below are examples. Retain existing approved filenames and use
their actual paths consistently; no file rename or state migration is required.

Keep both input files in the organization's protected configuration, not in Git
or unapproved sharing channels. Do not edit the shared profiles or copy the
network team's state. If required subnets or zones are missing, the platform
team provides them through its normal process; do not select `create` as a
workaround. Optional services need their additional inputs too.

The existing-network file selects **ownership**, not Private-only access.
Select the final access posture separately; a new private deployment still
needs the approved staged procedure. For an **already deployed gateway**, retain
its current source, complete inputs and authoritative state instead of creating
these files again. An existing Terragrunt pipeline can use the
[adapter](#optional-terragrunt-adapter) **instead of** the copied network file.

### How to read a step

| Label or format | What you do |
| --- | --- |
| `powershell` block | Run in PowerShell 7, from the stated directory. Run one step at a time; stop on an error. |
| `hcl` or `json` block | Edit the named configuration file in a text editor. Do **not** paste it into PowerShell. |
| `<...>` or a zero UUID | A placeholder you must replace with an approved value, not a usable example value. |
| **Expected** | Check this visible result before proceeding; command completion alone is not always enough. |
| **Stop** | Do not run the next step, change policy, open public access, or recreate resources to get past the problem. |

Copy only the selected branch. A line beginning with `#` in HCL is a comment;
to enable an optional example, uncomment the entire selected block, fill its
values and save the file. JSON does not accept comments or trailing commas.
Use **Ctrl+S** after editing; a file named `terraform.tfvars.txt` is not
`terraform.tfvars`.

## Runbook order

Use this order for a **new workload**. For a deployed gateway, use the
[update entry](#update-an-existing-gateway) instead; do not repeat bootstrap or
replace its complete inputs with a new base file.

| Step | Action | Continue only when |
| --- | --- | --- |
| 1 | [Prepare tools and the approved checkout](#prerequisites). | Versions and the working directory are correct. |
| 2 | [Prepare or retain the workload input file and state](#inputs-and-state). | The state owner is known, values are saved and the Azure context matches. |
| 3 | [Select create or existing networking](#network-foundation-create-or-existing). | One ownership file is selected; existing-mode IDs and the DNS owner are confirmed. |
| 4 | Complete the [platform handoff](#platform-handoff-before-a-plan). Select [test client](docs/private-connectivity.md#step-1-choose-your-test-client) and any [agent extension](#optional-private-hosted-agent) **before** the full plan. | Permissions, routes, policy, quota and optional inputs are approved. Do not run runtime tests yet. |
| 5 | Read [how to review a plan](#review-every-plan-before-apply), then prepare [monitoring](#monitoring-setup). | The destination is ready; the approved network posture was preserved. |
| 6 | Follow **one** path: [Private-only](#private-only) or [Public](#public). | The selected path's deployment and runtime gates pass. |
| 7 | If selected, deploy the [agent application](#optional-private-hosted-agent) separately. | Its own runtime identity, image pull and invocation have been checked. Otherwise skip this step. |
| 8 | Complete [acceptance and maintenance](#acceptance-and-maintenance). | Evidence, final drift result, remaining limits and cleanup ownership are recorded. |

The [Terragrunt adapter](#optional-terragrunt-adapter) is an alternative way to
connect the same inputs to an existing pipeline, not a second deployment to
run beside direct Terraform.

## Update an existing gateway

Use the [existing-gateway scenario](docs/scenarios/update-existing.md), not the
new-workload copy/bootstrap steps. A missing local state file does not make
the gateway new.

1. Confirm the current approved source revision, authoritative backend/state,
   stable naming and all input-file locations with the deployment owner. Use
   the existing initialization and identity process; do not create a second state.
2. Restore the [complete input selection](#compose-the-inputs), including
   optional/runtime inputs, ownership, current access and approved exceptions.
   Later object values replace whole objects, not individual nested fields.
3. Preserve disabled gateway/model public access and the existing endpoint
   approval mode. The shared private profiles select manual approval; changing
   that mode can replace a healthy endpoint. Retain any approved compatibility
   override after the access profile. Do not use the new-deployment Models-Public
   override for maintenance.
4. Follow only the procedure for the approved change:

   | Change | Canonical procedure |
   | --- | --- |
   | Maintain or complete an existing private deployment | [Existing private deployments](docs/private-connectivity.md#existing-private-deployments) |
   | Repair/update monitoring | [Current-state selection and monitoring procedure](docs/monitoring.md#choose-the-current-access-state) |
   | Add an approved Entra caller | [Access](#access), retaining existing keys and other bindings |
   | Other approved change, including an existing public deployment | The workload's existing pipeline and [full plan review](#review-every-plan-before-apply), preserving its approved configuration; not the new public-lab bootstrap |

5. Review a fresh plan, apply only approved changes and complete the selected
   [acceptance path](#acceptance-and-maintenance). No changes means no apply.

**Stop:** unexpected deletion/replacement, public reopening, missing inputs or
unclear state ownership. Changes to network ownership, endpoint placement or DNS
association ownership require a separate migration/handoff review, not a flag
flip. Never bypass `prevent_destroy` or reset state to make an update proceed.

## Prerequisites

### 1. Open the correct terminal and check tools

Open **PowerShell 7** from the Windows Start menu, or select that profile in
Windows Terminal. The older **Windows PowerShell** is not PowerShell 7. Run:

```powershell
$ErrorActionPreference = 'Stop'
$PSVersionTable.PSVersion
git --version
terraform version
az version
```

**Expected:** PowerShell major version `7`, an installed Git and Azure CLI,
and Terraform `1.11` or newer but below `2.0`. Keep the checked-in provider
lockfile; do not run `terraform init -upgrade` as a setup shortcut.
For the optional offline CI suite also check `python --version`; the documented
CI baseline is Python 3.12+ and Terraform 1.11.4.

**Stop:** if a command is not recognized or a version is incompatible, use the
organization's approved software installation process. Official instructions:
[PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows),
[Git](https://git-scm.com/downloads/win),
[Terraform](https://developer.hashicorp.com/terraform/install),
[Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli-windows).
Reopen PowerShell after installation and repeat the version checks. Do not
change machine-wide execution policy or install unrelated tools to bypass errors.

### 2. Open the approved source revision

Ask the workload owner for the repository URL, approved commit/tag and working
directory. Do not assume the newest remote branch is the release they approved.
For a **new checkout only**, create/select a work folder in File Explorer,
then replace the URL and revision below:

```powershell
Set-Location 'C:\work'
if (Test-Path -LiteralPath '.\ai-gateway_test') {
    throw 'Checkout already exists. Use the approved existing directory; do not overwrite it.'
}
git clone '<approved-repository-url>' ai-gateway_test
if ($LASTEXITCODE -ne 0) { throw 'Clone failed.' }
Set-Location .\ai-gateway_test
git switch --detach '<approved-commit-or-tag>'
if ($LASTEXITCODE -ne 0) { throw 'Cannot select the approved source revision.' }
```

For an **existing gateway**, open its approved deployment directory instead;
do not switch its revision or copy state using the new-checkout example.
From the repository root, enter the Terraform directory:

```powershell
Set-Location .\samples\terraform
Get-Location
Test-Path .\versions.tf
Test-Path .\profiles\network-existing.tfvars.json
git rev-parse HEAD
```

**Expected:** the path ends in `samples\terraform`, both checks return `True`,
and the SHA matches the approved revision. The network profile check also
detects an older checkout without the reuse implementation. The automated
acceptance runner needs a Git checkout and a clean source commit, not a ZIP
download. Environment-specific deployment input files remain ignored.

### 3. Confirm the platform prerequisites

Approve the full core scope: gateway, model deployments, **base agent account
and project, Storage, Premium registry and monitoring**, even without the
optional hosted-agent extension. Private-only closes gateway/model public access;
it does not make every supporting service private. Review the
[resource scope and boundaries](docs/architecture.md#1-base-sample-architecture).

Check model versions, capacity and optional hosted-agent availability in the
approved regions, inherited Azure Policy, required tags and permissions to
manage resources and scoped role assignments. Use the
[handoff table](#platform-handoff-before-a-plan); these approvals come from the
organization, not from installing Terraform.

This sample targets `Microsoft.ApiManagement/service` with SKU `AIGateway`.
Check availability for that exact resource contract, subscription and region;
the newer `Microsoft.ApiManagement/aigateways` resource is not a drop-in replacement.
Review Microsoft's [resource compatibility and lifecycle guidance](https://learn.microsoft.com/azure/api-management/ai-gateway-resource)
before deployment. This sample does not migrate resource types.

Have the platform owner confirm registration of the providers used by the selected
configuration: `Microsoft.ApiManagement`,
`Microsoft.Web`, `Microsoft.CognitiveServices`, `Microsoft.Storage`,
`Microsoft.ContainerRegistry`, `Microsoft.OperationalInsights`, `Microsoft.Insights`
and `Microsoft.Monitor`; also `Microsoft.Network` for networking, `Microsoft.Compute`
for the optional test VM, and `Microsoft.App` for private hosted agents.
The login step below includes a read-only registration check. Missing registration
belongs to the platform administrator's approved process, not an automatic fix
in this sample.

Public/private routing is independent of [Access](#access): callers can use an
API key or an Entra token with an invocation role. The gateway uses its own managed
identity for backend model calls. Adding Entra does not remove existing keys or
supply a missing private network route.

## Inputs and state

### 1. Confirm which state belongs to this workload

**Who:** the platform/pipeline owner, before the operator runs `terraform init`.
A Terraform **state** records which Azure resources this workload manages.
A **backend** is where that state is stored and coordinated.

- **New gateway:** obtain the approved workload backend configuration and
  initialization procedure. This root does not set up a shared remote backend
  for you. Plain `terraform init` without backend configuration uses local
  state; use that only for an explicitly approved local PoC.
- **Already deployed gateway:** retain its authoritative backend, working
  directory and complete current inputs. A missing local state file is not
  evidence of a new deployment; the state may be remote.
- **Existing platform network:** consume its IDs or dependency outputs. Its
  state remains with the platform owner; it is not the gateway's state.

**Stop:** if the state/backend owner or initialization procedure is unknown.
Do not initialize a second state, import the same resources elsewhere, copy a
colleague's state, or accept a backend migration/reconfiguration prompt as a
routine setup step.

<a id="2-create-or-select-your-base-input-file"></a>

### 2. Create or select a base input file

The tracked [.gitignore](.gitignore) excludes environment-specific `*.tfvars`,
`*.tfvars.json`, state and plans in this directory. The shared profiles and
`terraform.tfvars.example` are intentionally tracked. Ignoring a file does not
encrypt it or protect a file already tracked by Git.

For a **new workload with no existing input file**, run once:

```powershell
if (Test-Path -LiteralPath .\terraform.tfvars) {
    throw 'An input file already exists. Review it with its owner; do not overwrite it.'
}
Copy-Item -LiteralPath .\terraform.tfvars.example -Destination .\terraform.tfvars
```

In VS Code, choose **File > Open Folder**, open `samples\terraform`, then select
the new **terraform.tfvars**, not `terraform.tfvars.example`. Fill the table
below and save. Leave unneeded optional settings commented out.

For an **existing workload**, open its approved file instead; do not execute
the copy block. Point the session variable at that file:

```powershell
$workloadVarFile = (Resolve-Path -LiteralPath '.\terraform.tfvars').Path
# If the approved file is elsewhere, replace the path above with that actual path.
```

**Expected:** the path resolves to the saved file. For an input file **inside
this checkout**, check its ignore rule:

```powershell
git check-ignore -v -- $workloadVarFile
```

The output should identify the applicable ignore rule. If it does not, stop
before committing or sharing it. Never force-add inputs,
state, plan files or evidence. Review staged changes before any later commit.

### 3. Fill in the required values

| Value | Where it comes from and what to enter |
| --- | --- |
| `subscription_id` | Azure Portal **Subscriptions > approved workload subscription > Overview > Subscription ID**. Copy the UUID, not its display name or an ARM resource ID. |
| `environment_name` | Agree a short workload label with the platform owner: 1-32 lowercase letters, digits or hyphens, starting with a letter. For an existing workload keep its exact value. This is not an existing resource-group ID. |
| `publisher_email` | The approved operational contact address for this gateway, supplied by the workload owner. Replace `platform@example.com`. |
| `location` | The approved Azure region code for models, agent infrastructure and supporting services, not a display name. Example syntax: `swedencentral`; the example is not a region recommendation. The platform/model owner confirms availability and policy. |
| `gateway_location` | The approved gateway region code. In existing mode its integration subnet's VNet must be in this region. Create mode with the private-agent extension requires `location` to match this value. |
| `model_deployments` map keys | Agree client-facing aliases such as `gpt-mini`. Keep stable aliases for existing clients; they are not the underlying model name. |
| `model_name`, `model_version` | Have the model owner select the supported model/version in Microsoft Foundry's model catalogue/deployment configuration and copy the exact identifiers. The template's two models are examples, not quota reservations. |
| `sku_name` inside each model | Confirm the approved **model deployment type**, for example Global Standard versus an appropriate regional/data-zone offering. If omitted it defaults to `GlobalStandard`. This is not the gateway SKU. A resource's EU region alone does not establish EU-only model processing. See [deployment types](https://learn.microsoft.com/azure/ai-foundry/openai/how-to/deployment-types). |
| `capacity` | The model owner's approved allocation for that model, deployment type and region. Confirm available quota before planning. Capacity units are model/type-specific; do not assume one universal tokens-per-minute conversion. |
| `token_limit` | The agreed gateway token limit for callers. It is not the purchased model capacity and does not increase Azure quota. |

Keep all other already-approved inputs, including optional settings and
runtime identity files. There is no generic `resource_group_name` input:
the sample derives a **new workload group** from its naming inputs. After
deployment read its actual name with `terraform output -raw resource_group_name`.
Adopting an existing group is a separate integration change.

The **tenant ID** is needed for login/acceptance, not as another base tfvars
variable: in Azure Portal open **Microsoft Entra ID > Overview > Tenant ID**.
Ask the tenant administrator if it is not visible.

For optional identity fields, use an **object/principal ID**, not a client ID:

| Optional identity | Portal location or source |
| --- | --- |
| User or group in `gateway_access_principals` | **Microsoft Entra ID > Users / Groups > selected object > Overview > Object ID**. |
| Application service principal | **Microsoft Entra ID > Enterprise applications > selected application > Properties > Object ID**, not the app registration's Application (client) ID. |
| System-assigned managed identity | The actual Azure resource's **Identity > System assigned > Object (principal) ID**. |
| User-assigned managed identity | **Managed Identities > approved identity > Overview > Principal ID**, not Client ID. |
| Private hosted-agent runtime identity | Discover from the **deployed agent runtime/version** using the agent deployment process, not the project identity. Leave its optional input unset until that identity exists. |

Do not add Entra callers or agent runtime bindings merely to complete this
table. If the optional feature is not selected, its input is not required.

### 4. Sign in and verify the target

For this interactive setup, replace both placeholders and run:

```powershell
$ErrorActionPreference = 'Stop'
$tenantId = '<approved-tenant-id>'
$subscriptionId = '<approved-workload-subscription-id>'
az login --tenant $tenantId
if ($LASTEXITCODE -ne 0) { throw 'Login failed.' }
az account set --subscription $subscriptionId
if ($LASTEXITCODE -ne 0) { throw 'Cannot select the approved subscription.' }
$accountJson = az account show --output json --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the Azure context.' }
$account = $accountJson | ConvertFrom-Json
if ($account.id -ine $subscriptionId -or $account.tenantId -ine $tenantId) {
    throw 'Wrong tenant or subscription. Stop and contact the deployment owner.'
}
$account | Select-Object name, id, tenantId
```

**Expected:** the displayed name/IDs match the approved workload subscription
and tenant, and `subscription_id` in the saved input file matches too. If PIM
is used, activate only the approved role/scope for the agreed duration through
the organization's process; a successful login does not activate permissions.
For pipelines, use their existing approved identity flow instead of interactive
`az login`. Do not copy personal tokens or substitute a lab/admin account.

To look up a region's code after login, replace the display-name placeholder:

```powershell
az account list-locations --subscription $subscriptionId `
    --query "[?displayName=='<approved-region-display-name>'].{Code:name,Name:displayName}" --output table
if ($LASTEXITCODE -ne 0) { throw 'Region lookup failed.' }
```

This maps names only; it does **not** prove model/gateway availability or quota.
Check the required provider registrations with the platform owner. For example:

```powershell
az provider show --namespace Microsoft.Network --subscription $subscriptionId `
    --query registrationState --output tsv
if ($LASTEXITCODE -ne 0) { throw 'Cannot verify provider registration.' }
```

**Expected:** `Registered`; repeat for the providers required by the selected
features. A different result or access denial goes to the platform administrator,
not an automatic registration or permission expansion.

Have the owner review any pre-existing `ARM_*`, `AZURE_*`, `TF_VAR_*` or
`TF_CLI_ARGS*` environment settings; they can alter credentials or inputs.
Do not display secret values or silently remove pipeline authentication.

### 5. Initialize only the approved workload backend

Run the platform's approved initialization command in the confirmed directory.
The following plain command is appropriate only if that is the approved
procedure (including an explicitly approved local-state PoC):

```powershell
terraform init
if ($LASTEXITCODE -ne 0) { throw 'Initialization failed; do not continue.' }
terraform fmt -check -recursive
if ($LASTEXITCODE -ne 0) { throw 'Formatting needs review; do not rewrite shared files blindly.' }
terraform validate
if ($LASTEXITCODE -ne 0) { throw 'Configuration validation failed.' }
```

**Expected:** initialization uses the agreed backend and validation succeeds.
These checks do not deploy resources or prove Azure permissions, DNS or quota.
Inputs supplied with `-var-file` are evaluated during planning, not by `validate`.

Every later plan must include **all** approved input files. The examples show
the base file explicitly; put additional input files before the
selected ownership file and the final private-access profile. Do not copy an
old saved plan into a new session.

**Next:** select the network foundation below.

## Network foundation: create or existing

Choose **one** row and set its variable in the same PowerShell session used below.
The ownership profile does not select public access or enable private networking.
`create` is the compatibility default; `existing` requires a private-access profile.

| Starting point | Set the ownership file |
| --- | --- |
| No gateway network/DNS foundation | `$networkOwnershipFile = 'profiles\network-create.tfvars.json'` |
| Approved, centrally managed subnets and DNS zones | `$networkOwnershipFile = 'network-existing.environment.tfvars.json'` |

For **create**, [network-create.tfvars.json](profiles/network-create.tfvars.json)
keeps the existing sample names, Terraform addresses and address defaults. With
private networking enabled, Terraform creates the gateway VNet/subnets, NSGs,
private DNS zones and links. It does **not** create a corporate hub, firewall,
resolver or landing zone.

For **existing**, first make a new, untracked copy of
[network-existing.tfvars.json](profiles/network-existing.tfvars.json) named
`network-existing.environment.tfvars.json`. Replace **every complete example
resource-ID value** with its approved ID; use the
[replacement checklist](#replacement-checklist-for-existing-network-inputs).
Never overwrite an existing approved input file. The minimal example supplies
gateway integration, separate per-service
gateway/model endpoint **fields** and the four core DNS zones. The three core
subnet fields may use two physical subnets: the endpoint fields may share an
approved subnet, separate from integration. Optional storage
endpoints, private agents and the test VM remain disabled by default; enabling
one also requires its additional network inputs. See
[required inputs and permissions](docs/private-connectivity.md#existing-network-prerequisites).

With private networking enabled, both choices still create **new workload-owned
private endpoints**. Existing mode
reads the actual subnet/VNet location, IPv4 CIDRs, delegations and gateway NSG attachment through AzAPI; it
does not edit central networks, subnet policies, NSGs, UDRs, firewall, resolver,
DNS zones or links. Different services can use different approved endpoint
subnets/VNets, resource groups and locations, but all endpoint subnets must be in
the workload `subscription_id`: the new endpoints retain workload resource-group
ownership and must share their VNet's subscription/region. Central DNS zones may
be in another subscription. Cross-subscription endpoint placement/ownership is
not implemented. It does not import existing private endpoints, resource groups,
Foundry accounts or other application resources.

Network and DNS are separate logical concerns, but only the two paired ownership
modes are supported here: create both foundations, or reuse both. Missing reuse
inputs fail; there is no silent creation fallback or mixed-ownership mode.

### Existing-network connectivity reference

This reference uses **`existing` networking** with the gateway/model
**`private-only` target after approved staged setup**. Private endpoint subnet
roles may share an approved subnet; the delegated gateway integration subnet
remains separate. No VNet count or hub/spoke design is prescribed.

![Two private paths with platform-owned subnet roles, resolver-mediated DNS lookups and the four required central private DNS zones](docs/images/02-network-and-dns.svg)

[Open full-size SVG](docs/images/02-network-and-dns.svg)

Blue arrows show HTTPS model traffic; purple dashed arrows show DNS queries
and replies through the existing resolver.

| Path | Network role |
| --- | --- |
| Private client to gateway | Client DNS resolves the gateway hostname to its private endpoint. The client sends an authenticated HTTPS request over the approved private route. |
| Gateway to model | Gateway outbound VNet integration reaches the model's private endpoint. The gateway authenticates with its own managed identity. |
| Name resolution | The existing resolver and central zones resolve the gateway and model names. DNS queries are separate from model requests. |

Central zones and forwarding remain platform-managed. Workload private endpoints
still need a completed DNS association and working resolution before private
calls. The [request flow](docs/architecture.md#end-to-end-private-request-flow)
explains the runtime sequence.

<a id="find-resource-ids-and-fill-in-your-customer-file"></a>
<a id="find-resource-ids-and-fill-in-your-network-input-file"></a>

### Find resource IDs and fill in the network input file

The network/DNS team can complete these inputs in the approved configuration.
Do not share passwords, keys or Terraform state through unapproved channels.
A resource ID is the **full Azure resource address beginning with
`/subscriptions/...`**, not a resource name, IP address or just a subscription UUID.
Keep these infrastructure details in the approved internal configuration.

#### 1. Choose approved resources

Ask the network/DNS owner which subnets and central zones this workload should
use. Do not select an arbitrary existing subnet: gateway integration needs a
dedicated, correctly delegated subnet with an attached network security group
(NSG), separate from private endpoint subnets.
See the [subnet and permission prerequisites](docs/private-connectivity.md#existing-network-prerequisites).
If a suitable subnet does not exist yet, create it through the usual platform
provisioning process, then pass its ID here; do not switch to `create` merely
to fill a missing input.

Before proceeding, have the owner complete
[the six small NSG checks](docs/private-connectivity.md#confirm-the-gateway-subnets-network-security-group).
An NSG merely existing elsewhere is not sufficient. If the subnet shows
**Network security group: None**, stop until the platform process associates
the approved NSG and checks outbound rules. The workload keeps the same subnet
ID; no separate NSG ID or new workload-owned NSG is needed.

#### 2. Find the IDs in the Azure Portal

Sign in to the correct directory and check the subscription filters. Activate
the approved PIM role if required. If a resource is not visible, ask its owner
for the ID and the necessary scoped permissions; do not create a duplicate.

| What you need | Where to find it |
| --- | --- |
| Workload subscription ID | **Subscriptions > approved workload subscription > Overview**: copy **Subscription ID**. This is the UUID for the base input `subscription_id`. |
| Subnet resource ID | **Virtual networks > approved VNet > Overview > JSON View**: find the intended subnet by its `name` inside `properties.subnets`, then copy that subnet's entire `id`. Do **not** copy the VNet's top-level `id`. Repeat for each required subnet. |
| Private DNS zone resource ID | **Private DNS zones > approved zone > Overview > JSON View**: copy the top-level `id`. Check the zone name, resource group and subscription with the DNS owner. Use the private DNS **zone** ID, not a public DNS zone, resolver resource ID or resolver IP address. |

The endpoint subnets, and the optional test-client subnet if enabled, must
belong to the workload `subscription_id`. Central DNS zones may belong to a
different subscription. Copy each complete ID from its actual resource rather
than replacing every subscription UUID with the same value.

<a id="3-fill-in-your-own-configuration-file"></a>

#### 3. Fill in the configuration file

In `samples\terraform`, copy
[profiles\network-existing.tfvars.json](profiles/network-existing.tfvars.json)
to **`network-existing.environment.tfvars.json`**. Keep the shared example unchanged;
if an approved input file already exists, edit that file without overwriting
it with the template. Follow [Inputs and state](#inputs-and-state) to keep input
files out of Git; never force-add them.

For a **new input file only**:

```powershell
if (Test-Path -LiteralPath .\network-existing.environment.tfvars.json) {
    throw 'Environment-specific network inputs already exist. Review that file instead of overwriting it.'
}
Copy-Item -LiteralPath .\profiles\network-existing.tfvars.json `
    -Destination .\network-existing.environment.tfvars.json
```

Open the copied file in VS Code. Replace each complete resource-ID string
inside its existing quotes, using the table below, then press **Ctrl+S**.

Set the workload `subscription_id` in the base inputs, normally
`terraform.tfvars`. In the copied JSON file, keep
`"private_network_mode": "existing"` and replace the example values under
**`existing_private_network`** using this mapping:

| Field under `existing_private_network` | Approved resource ID to enter |
| --- | --- |
| `gateway_subnet_id` | The gateway's dedicated outbound-integration subnet, with its approved NSG already attached. |
| `endpoint_subnet_ids.gateway` | The subnet for the gateway's inbound private endpoint. |
| `endpoint_subnet_ids.models` | The subnet for the model account's private endpoint. |
| `private_dns_zone_ids.gateway` | The central zone named `privatelink.azure-api.net`. |
| `private_dns_zone_ids.cognitiveservices` | The central zone named `privatelink.cognitiveservices.azure.com`. |
| `private_dns_zone_ids.openai` | The central zone named `privatelink.openai.azure.com`. |
| `private_dns_zone_ids.services` | The central zone named `privatelink.services.ai.azure.com`. |

The dotted field names in the table describe the existing nested JSON structure;
replace the string values in that structure rather than adding literal dotted
keys. Keep quotes, commas and braces intact and remove all example IDs.
The gateway and model endpoints may share an approved endpoint subnet, but
neither may use the delegated integration subnet.

The starter file covers gateway/models only. If you enable storage endpoints,
private hosted agents or the test VM, also supply the
[additional required inputs](docs/private-connectivity.md#existing-network-prerequisites).
Confirm [who manages the DNS zone groups](#choose-the-dns-zone-group-owner):
keep `workload` only if this Terraform deployment should create those associations;
choose `platform` when central policy or automation owns them.

Check the saved JSON locally:

```powershell
$networkInput = Get-Content -LiteralPath .\network-existing.environment.tfvars.json -Raw | ConvertFrom-Json
if ($networkInput.private_network_mode -cne 'existing') { throw 'Expected existing network mode.' }
if (Select-String -LiteralPath .\network-existing.environment.tfvars.json `
        -Pattern '00000000-0000-0000-0000-000000000000|<[^>]+>' -Quiet) {
    throw 'Replace the remaining network placeholders before continuing.'
}
git check-ignore -v -- network-existing.environment.tfvars.json
```

**Expected:** no JSON/placeholder error, and an ignore-rule result. This checks
syntax and obvious placeholders only; Terraform's later plan reads the actual
subnets and validates their regions, prefixes, delegations and gateway NSG
attachment. It does not prove effective firewall/NSG rules or runtime connectivity.

#### 4. Connect the file to the deployment process

Set `$networkOwnershipFile = 'network-existing.environment.tfvars.json'` in the
PowerShell session for the runbook. This file is **not automatically loaded**:
include it explicitly alongside the complete base inputs and private-access
profile as shown in [Compose the inputs](#compose-the-inputs). It selects network
ownership, not private access, and does not by itself deploy anything.

Correct IDs alone do not establish routes, DNS resolution or permissions.
Have the platform team confirm those prerequisites before the reviewed plan and
private-path acceptance. If this workload is already deployed, retain its state
and ownership until the separate migration review described below is complete.

**Already using Terraform/Terragrunt?** Instead of copying IDs manually, expose
the approved subnet and zone IDs as outputs of the existing platform modules
and map them into this workload. The [Terragrunt adapter](#optional-terragrunt-adapter)
shows the expected output names and dependency wiring; adapt them to the platform
modules and keep the authoritative backend/pipeline. This does not require
sharing or copying the platform's state into the gateway deployment.

### Compose the inputs

The order is **base inputs → additional input files → network ownership →
private-access profile → explicitly approved endpoint compatibility override**.
Keep the complete selection on every full, targeted and drift plan. Later
assignments replace the **whole variable**, not just nested keys: keep one
complete `existing_private_network` object, including any optional fields, in
its approved input source. Do not split partial objects across overlays.
Resolve the two selected files, without changing that selection:

```powershell
if (-not $workloadVarFile -or -not $networkOwnershipFile) {
    throw 'Select the approved base and network ownership files first.'
}
$workloadVarFile = (Resolve-Path -LiteralPath $workloadVarFile).Path
$networkOwnershipFile = (Resolve-Path -LiteralPath $networkOwnershipFile).Path
```

Choose **one** additional-file line. These are other approved workload inputs,
not the ownership file or access profile:

| Deployment inputs | Set in PowerShell |
| --- | --- |
| No additional input files | `$additionalVarFiles = @()` |
| Additional files, for example a deployed agent's runtime identity | `$additionalVarFiles = @('C:\secure\private-agent-runtime.tfvars.json')` using the actual approved path; add other paths inside the same array if required. |

Turn that selection into the arguments used below:

```powershell
$additionalVarFiles = @($additionalVarFiles | ForEach-Object {
    (Resolve-Path -LiteralPath $_).Path
})
$additionalInputArgs = @($additionalVarFiles | ForEach-Object { "-var-file=$_" })
```

Choose **one** endpoint-compatibility line too:

| Existing endpoint choice | Set in PowerShell |
| --- | --- |
| New endpoint, or an already approved manual endpoint | `$endpointCompatibilityArgs = @()` |
| Preserve an existing healthy automatic endpoint, specifically approved by the workload owner | `$endpointCompatibilityArgs = @('-var=gateway_private_endpoint_manual_approval=false')` |

The second case prevents the shared profile from silently selecting a replacement
manual endpoint. Do not invent other overrides or use this mechanism to reopen
public access. The automatic acceptance runner cannot append these post-profile
overrides; use [manual acceptance](docs/acceptance.md) when one is required.

**Expected:** both files exist. Reading/selecting them does not deploy anything.
The actual plan commands appear in the monitoring and selected deployment steps.
The private-only profile is the desired final posture, **not** a verified
private-from-first-create shortcut. The explicitly approved intermediate stages
below change only the private-access profile/temporary override, not the chosen ownership inputs.
Never select a profile or override that reopens disabled gateway or model access.
Do not add a later override that reopens public access.

Do not switch an already-deployed `create` network to `existing` as a normal
update: Terraform can propose deleting the sample-managed foundation. Retain the
authoritative backend, state, resource addresses and ownership until a separately
reviewed state/migration plan is approved. The created VNet has a
`prevent_destroy` guard that blocks accidental ownership mode changes; do not
bypass it. Do not copy state or import the same central resources into
another owner.

### Choose the DNS zone-group owner

- **`private_dns_zone_group_management = "workload"` (default):** Terraform writes
  the new endpoints' zone-group associations to the selected zones. In existing
  mode this needs explicit, scoped permissions on those zones and the endpoints;
  owning the endpoint alone does not grant central DNS access.
- **`"platform"` (existing mode only):** Terraform leaves zone groups to Azure
  Policy or the central deployment process. Still supply all required zone IDs.
  The platform must complete endpoint associations/records and resolver readiness
  before private calls, agent use or access closure. Terraform intentionally
  does not wait for policy or manage central records/links. Do not let two
  processes own the same group.

Changing an existing deployment between workload/platform DNS ownership is a
separately reviewed state handoff, not a routine flag flip. Review any zone-group
removal/recreation and DNS continuity with both owners; no automatic import or
ownership transfer is performed.

Terraform success does not prove DNS propagation, firewall routing or runtime
connectivity. A central resolver is valid without a direct DNS-zone link to every
spoke; the network/DNS team retains the approved links/forwarding design.

## Platform handoff before a plan

**Who:** the workload operator gathers these confirmations from the named
owners. A copied ID is not a permission grant or a connectivity test.

The ownership boundaries below describe **`existing` mode**. For `create`,
the sample instead owns its new network/DNS foundation; approve the new address
range and check overlap as described in [network foundation](#network-foundation-create-or-existing).

![Platform networking and DNS retain their ownership and state; workload Terraform consumes resource IDs and creates separate application resources and private endpoints](docs/images/03-resource-ownership.svg)

[Open full-size SVG](docs/images/03-resource-ownership.svg)

These are management boundaries, not network boundaries. Passing resource IDs
does not import platform resources or merge Terraform states. Each endpoint has
one DNS zone-group owner; central zones remain platform-owned in either case.
The same infrastructure team may operate both platform and workload roles.

| Area | Owner and Terraform boundary | Confirmation needed before planning |
| --- | --- | --- |
| Gateway workload and state | Workload team owns the new application resources and private endpoints in its approved workload state. Existing platform state stays separate. | Exact source revision, subscription/tenant, backend, naming, current gateway deployment status and final access posture. Existing networking does not import an existing gateway or application resource. |
| VNets, subnets and network security groups | Network team retains the resources and their state; workload Terraform only reads approved subnet/VNet details. | Complete integration/endpoint subnet IDs, delegations, attached gateway NSG, available addresses and service-region placement. |
| Routes, firewall and DNS resolver | Network/platform team retains routes, firewall, resolver and forwarding; this sample does not create or change them. | Client-to-gateway and gateway-to-model routes, DNS forwarding and control-plane/identity egress. Optional VM and agent routes need separate approval. |
| Central private DNS zones and VNet links | DNS team retains zones, links and their state. The workload references zone IDs, not ownership of those resources. | Exact required zone IDs and the approved resolution design; a direct zone link to every spoke is not required when central resolution is used. |
| Private endpoint DNS zone groups | **One owner:** workload Terraform with `workload`, or central Policy/automation with `platform`. This does not transfer ownership of the zones. | Agree who finishes associations/records after endpoint creation and verifies resolver results. Use the [DNS ownership choice](#choose-the-dns-zone-group-owner); never let both processes own the same group. |
| Deployment permissions | Identity/platform administrator grants scoped access; knowing a resource ID does not grant access. | Effective deploy/read/join/endpoint/approval and role-management permissions, PIM duration and deny assignments. Workload-managed zone groups also need access to the specified central zones. |
| Models | Model owner approves model selection and allocation; the sample creates its workload model deployments. | Exact model names/versions, deployment geography, quota/capacity and a billable test allowance. |
| Policy and access sequence | Security/platform owner approves the deployment; this sample does not relax central policy. | Region/type/tag policy and the entire access sequence. Temporary public access needs explicit approval, not just approval of the final private design. |
| Testing and operation | Test/operations owner selects the client and owns evidence, cleanup and ongoing operation. The sample VM is optional. | Existing private client or approved test VM, test permissions, evidence location and cleanup/monitoring responsibility. |

Do not demand `Approved` endpoints before they have been created. Those are
**post-apply gates**, explained in the
[endpoint and DNS readiness steps](docs/private-connectivity.md#endpoint-and-dns-readiness).
For platform DNS, agree how the operator is notified when central automation
finishes; Terraform does not wait for that handoff.

**Stop:** missing IDs, permissions, quota, routing or approvals go to the
corresponding owner. Do not select a convenient but unrelated subnet, request
Owner for the test VM, create duplicate DNS zones or disable policy.

### Optional Terragrunt adapter

The platform maintainer can use the
[Terragrunt integration procedure](docs/reference.md#optional-terragrunt-adapter)
instead of direct input files. It uses the same root and approved workload
backend, not another deployment or a copy of platform state. The former
subsection links below now point to that procedure.

#### 1. Identify the existing live units and workload state

See [live units and workload state](docs/reference.md#1-identify-the-existing-live-units-and-workload-state).

#### 2. Confirm available outputs before editing the adapter

See [the dependency-output contract](docs/reference.md#2-confirm-available-outputs-before-editing-the-adapter).

#### 3. Place and adapt the two workload files

See [adapter placement and complete inputs](docs/reference.md#3-place-and-adapt-the-two-workload-files).

#### 4. Use the existing pipeline, for this workload unit only

See [single-unit execution and helper integration](docs/reference.md#4-use-the-existing-pipeline-for-this-workload-unit-only).

## Access

Grant identity-based access with **Microsoft Entra ID**, or manage **API keys**.
The [end-to-end private request sequence](docs/architecture.md#end-to-end-private-request-flow)
shows client authentication, DNS and the gateway's separate backend identity.
For an additive Entra change, use the [Access reference](docs/reference.md#access)
for the complete input example, object-ID/role-scope contract and client probes.
Retain the existing state, full inputs, access posture and endpoint exceptions;
extend the approved principal map without replacing unrelated settings.

Use audience `https://azure-api.net/aigateway`; SDK clients calling as themselves
request `https://azure-api.net/aigateway/.default`. Custom apps signing in users
need delegated `https://azure-api.net/aigateway/Data.All` consent plus the user's
invocation role. This custom-app consent setup does not apply to managed identities,
client credentials or built-in Azure CLI/PowerShell clients. Send
`Authorization: Bearer <token>`, never an ARM or model-backend token. See the
[portal security and identity guide](https://ai.gateway.azure.com/docs/security-identity).

Run the reference's billable probes **after deployment** from the selected route,
verifying authorized/unauthorized callers and fresh telemetry. Its dated
managed-identity evidence is not custom delegated-user client verification.

**Not Entra-only:** keys are neither disabled nor deleted. The existing agent and
private VM retain their key-reader roles and API-key calls. The gateway's backend
Foundry User binding stays unchanged. An empty map also does not remove roles
managed outside this sample.

## Review every plan before apply

**Who:** the workload operator and the owner authorized to approve the change.
**Where:** the same PowerShell session, source revision, backend and input files
used to create the plan.

1. Run the plan command for the **selected step**, saving its `.tfplan` file.
   Stop if it fails; an older file with the same name is not a valid new plan.
2. Run that step's `terraform show <saved-file>.tfplan` command. Read the
   individual resource changes, not just the final action count.
3. Use the table below and obtain approval for the actual changes and cost.
4. Only then run `terraform apply <that-same-file>.tfplan`. **Applying a saved
   plan does not ask for another interactive confirmation.** Do not paste the
   plan and apply blocks together before reviewing.
5. Wait for successful completion and perform the step's Azure/DNS/runtime
   checks. If an apply fails partway through, retain its state and investigate;
   it is not safe to assume that nothing was created.

| Plan display | Meaning and review action |
| --- | --- |
| `+` create | A new resource. Check its type, subscription/group, subnet, access posture, role scope and cost. |
| `~` update in-place | An existing resource changes. Inspect the old/new values; in-place does not mean harmless. |
| `-` destroy | A deletion. Stop unless that exact deletion and any data loss were separately approved. |
| `-/+` or `+/-` replacement | Terraform recreates a resource. Stop for separate review of downtime, identity, data and address changes. |
| `<=` read | A data-source read, not ownership of the referenced resource. Existing-mode subnet/VNet reads are expected. |
| Output changes | Exported metadata changes. They are not a substitute for checking resource actions and actual connectivity. |

For **existing-network mode**, new workload private endpoints, workload
resources and approved role assignments are expected. Workload-owned DNS
**zone groups** may be new even though the DNS **zones** are reused. The plan
must not create, change or remove centrally managed VNets, subnets, NSGs, routes,
resolver, central zones or links. In `platform` DNS mode this Terraform must
not also take ownership of the endpoint zone groups.

For **create mode**, the approved sample network/DNS foundation is expected,
not a new corporate hub/firewall. For either mode, reject unapproved permission
expansion, resource replacement and public-access reopening. An existing
deployment must retain stable naming, resource addresses and ownership.
There is no universally correct resource count; optional features and
service-managed monitoring resources affect it.

With `-detailed-exitcode`, exit `0` means no changes, `1` means failure, and `2`
means changes were found. Exit `2` is not automatic permission to apply. A
saved deployment plan without that flag normally exits `0` even when it proposes
changes. Keep plan files/output protected; never publish them with the source.

## Monitoring setup

The gateway exporter needs real OpenTelemetry Protocol (OTLP) endpoints and a
linked Data Collection Rule (DCR), discovered from Application Insights.
Use [Gateway OpenTelemetry setup](docs/monitoring.md#choose-the-current-access-state)
as the **only executable monitoring procedure**:

1. Retain the [complete inputs](#compose-the-inputs) and select the current access
   state there. Never drop ownership/private inputs or reopen a closed endpoint.
2. Complete [Stage A: prepare and verify the destination](docs/monitoring.md#stage-a-prepare-and-verify-the-destination),
   including targeted-plan review and actual endpoint/DCR readiness. Do not
   repeat its apply if it has already completed.
3. For a new workload, return to [Public](#public) or [Private-only](#private-only)
   and create a **fresh full plan**. That configures the exporter and its DCR
   publisher role. For an approved existing-exporter repair, follow
   [Stage B](docs/monitoring.md#stage-b-repair-an-existing-exporter) instead.

**Expected:** verified destination endpoints/linkage, with no permission,
provisioning or timeout error. Metadata readiness is not telemetry delivery
proof; acceptance still needs fresh requests. Never guess IDs or broaden access.
An immutable exporter-kind failure needs the
[separately approved replacement procedure](docs/monitoring.md#existing-legacy-exporter-immutable-kind),
not automatic deletion/recreation.

## Public

Use for a **deliberate new public lab** only, with explicit approval for public
gateway/model endpoints. It is the Terraform default, **not** a required
prerequisite for Private-only. A deployed gateway uses the
[update entry](#update-an-existing-gateway) and its full approved configuration;
do not use new-lab defaults to repair or update it.

```powershell
terraform plan -input=false "-var-file=$workloadVarFile" @additionalInputArgs `
    "-var-file=$networkOwnershipFile" @endpointCompatibilityArgs -out=deployment.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Public deployment plan failed.' }
terraform show deployment.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the saved public plan.' }
```

**Expected:** the reviewed public configuration, complete approved workload
inputs and `create` ownership, with no removal of an existing private setup.
Review [every planned change](#review-every-plan-before-apply). Only after
approval, execute the saved plan:

```powershell
terraform apply deployment.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Public deployment apply failed; stop.' }
```

**Next:** run the billable smoke test from the selected public client, then
check drift with the same inputs:

```powershell
.\scripts\Test-ModelAliases.ps1
terraform plan -input=false "-var-file=$workloadVarFile" @additionalInputArgs `
    "-var-file=$networkOwnershipFile" @endpointCompatibilityArgs -detailed-exitcode
$driftExit = $LASTEXITCODE
if ($driftExit -ne 0) { throw "Drift check exit $driftExit; review before continuing." }
```

The probe makes billable calls to every configured chat-completions alias from
the deployment client. All aliases must answer; final plan exit `0` means no changes,
`1` means an error, and `2` means changes requiring review.

## Private-only

The final [private-only profile](profiles/private-only.tfvars.json) disables
**both gateway and model public access**. Private clients reach the gateway's
private endpoint; separate gateway outbound VNet integration reaches the model
private endpoint. Private DNS, endpoint approval and working routes are all required.
This is not a claim that all supporting services are private.

**Already deployed?** Use [existing private deployments](docs/private-connectivity.md#existing-private-deployments),
retaining complete inputs, state/backend, disabled access and the approved
endpoint mode. Never repeat temporary-public staging on an already-private
gateway or backend.

**New private gateway:** follow the canonical
[private-path runbook](docs/private-connectivity.md#step-1-choose-your-test-client).
Its bounded sequence prepares private connectivity, proves the selected private
route, closes model access, then closes gateway access and repeats acceptance.
The initial Models-Public exception requires explicit approval and belongs only
to that new-deployment path. The intermediate `private-connectivity` profile
is not a third deployment path or final acceptance.

Choose an **existing private client** or **optional sample VM** before the full
plan. All callers, including agents and CI, need their own route and DNS before
gateway closure. Wait for actual provisioning, approval and DNS readiness;
inspect asynchronous failures rather than reopening access. If temporary public
access is prohibited, stop: this guide does not establish private-from-first-create.

**Expected:** the selected clients can use the private route, both public-access
settings are disabled, the full drift plan has no changes and authenticated
public-network rejection is demonstrated separately. A DNS/inference check alone
is not full acceptance.

**Return here afterward:** perform the optional agent application step below,
or skip directly to [acceptance](#acceptance-and-maintenance).

## Optional private hosted agent

If selected, prepare the additive infrastructure through
[Configure new agent accounts from the start](docs/private-hosted-agent.md#configure-new-agent-accounts-from-the-start)
and [Prepare an additive plan](docs/private-hosted-agent.md#prepare-an-additive-plan).
Network injection must be selected **before the new account is created**; it
cannot simply be added to an existing account. The base agent account/project,
Storage and Premium registry remain core resources when this extension is off.

After infrastructure and private connectivity are ready, the application owner
follows the separate [deployment and acceptance gates](docs/private-hosted-agent.md#deployment-and-acceptance-gates):
use the **new** `private_hosted_agent` project, deploy the image/application from
an approved private executor, discover the real runtime identity, verify runtime
AcrPull and bind narrow gateway key retrieval. Terraform does not deploy the
application. Retain all runtime inputs and never store keys in state or files.
Finish with [repeatable operation and cleanup](docs/private-hosted-agent.md#repeatable-operation-after-deployment).

Changing `enable_private_test_client` changes the private agent's key-reader role.
Terraform replaces that role assignment rather than updating its immutable role.
Upgrading an older assignment also requires a one-time replacement; review the
plan and allow for a brief interruption of the agent's key retrieval.

## Acceptance and maintenance

Require fresh results in the selected environment, not screenshots from another
deployment: each alias succeeds, missing/invalid gateway keys are rejected, expected
roles/connections and private DNS are correct, and gateway/backend telemetry
correlates to the same request. For Private-only, a **valid authenticated request
from outside the private route** must receive explicit network denial; a 401,
authentication-related 403, timeout or DNS error is not equivalent.

For a hosted agent, invoke a fresh session/version and correlate its response to
successful gateway **and intended model backend** spans in `OTelSpans` by `TraceId`
and time window. Confirm gateway/model/Foundry public settings, cleanup of temporary
roles/VMs, and a no-change plan with **all** original and runtime inputs.

Choose **one** acceptance execution path:

| Test client | Procedure | Important limit |
| --- | --- | --- |
| Approved existing private client, no sample VM | [Existing-client private checks](docs/private-connectivity.md#test-from-an-existing-private-client), then [manual acceptance](docs/acceptance.md), including the [six-check manual portal review](docs/acceptance.md#8-record-the-manual-portal-review). | The VM-based runner cannot certify this client. Keep operator-attested evidence and mark unperformed checks; do not fabricate a runner PASS. |
| Optional sample VM | [Optional sample-VM acceptance runner](docs/end-to-end.md), after smoke-test deallocation. | Requires the VM ID even for diagnostics, full inputs, VM initially deallocated, explicit model/compute approval and a separate portal review. Public rejection and agent runtime are still separate. |
| Intentionally public deployment | [Manual acceptance](docs/acceptance.md), including its [manual portal review](docs/acceptance.md#8-record-the-manual-portal-review), on that approved public route. | It is not private-route evidence. |

For the optional sample-VM report, use the runner's
[complete parameter selection](docs/end-to-end.md#2-read-only-backend-checks),
then its [explicit runtime step](docs/end-to-end.md#3-explicit-private-runtime-and-telemetry).
It reads ARM, runs a full drift plan and writes local reports; the runtime flag
also starts the VM, uses Run Command, makes billable calls and deallocates it.
Keep every approved file in `-AdditionalVarFile`; the access profile is last.
Use manual acceptance if a post-profile compatibility override is needed.

Both routes require the [shared portal checklist](docs/acceptance.md#ai-gateway-portal-checklist).
The VM manifest validator checks evidence completeness, **not the browser**.
Never treat blocked or unexecuted checks as passed.

For platform-managed DNS, acceptance requires delivered private-endpoint zone
groups with the exact supplied zone IDs; group names and Terraform ownership do
not matter. Missing bindings fail, so manual-record-only DNS is not certified.
Gateway/model/optional-storage DNS and private inference/authentication still
need proof; registry image-pull runtime is a separate check.

Use an approved, access-restricted report directory. A `BLOCKED` result is not
a pass or necessarily a broken gateway: inspect which gates were not run.
The [report interpretation](docs/end-to-end.md#read-the-result-before-proceeding)
explains the next action.

<a id="handover-checklist"></a>

### Deployment acceptance checklist

Review the [version and verification scope](docs/reference.md#version-and-verification-scope),
then complete this record for **the target deployment**. A reviewed source revision
does not replace acceptance in that environment.

| Record in the protected acceptance record | Required result or named remaining item |
| --- | --- |
| Approved commit and workload owner | Exact revision, authoritative backend and operating contact are known. Do not attach raw state to the acceptance record. |
| Input file locations and choices | Base/additional files, create/existing ownership, DNS owner, access profile and any runtime-identity inputs are recorded without keys. |
| Networking and authentication | Endpoint approval, actual private DNS, per-alias calls, same-route invalid/missing-key checks and required public-network rejection are evidenced. |
| Monitoring | Fresh requests correlate with gateway/backend telemetry. All six portal checks and a matched numeric metrics comparison are evidenced through the VM manifest or the explicitly manual portal record. |
| Optional services | Agent/image/registry or Blob tests have their own results; unrelated successful model calls do not certify them. |
| Final drift and open issues | Full plan uses every original input and exits `0`; otherwise the exact difference/failure remains open. `NOT RUN`, `BLOCKED` and `not verified` are not relabeled as passed. |
| Cleanup and costs | Any deployed sample VM is confirmed **deallocated** (otherwise record `not deployed`), temporary job-created roles are removed, retained roles are preserved, and continuing service/storage costs have an owner. |

Run maintenance tests only in a **separate clean checkout without deployment
tfvars or state**, as described in [offline checks](docs/reference.md#offline-checks).
The helper may download providers and writes local files; it does not touch Azure.
Do not run
generic fixtures against a configured workload directory. The operator can
retain the approved revision's CI result instead of rerunning maintenance tests.
Azure Policy can deny, modify or create related resources; inspect actual posture
and drift after remediation instead of blindly undoing enforced settings.

Model calls, Premium ACR, Storage, monitoring and optional compute incur charges.
The gateway preview has no SLA. Before cleanup, review a destroy plan, data-retention
requirements, `prevent_destroy` guards, externally managed roles and Azure-managed
monitoring groups. Destroying Terraform resources does not certify removal of all
service-managed resources or charges; do not bypass protections automatically.

## If something fails or you open a new terminal

**Stop at the failed step.** Record the step, UTC time, approved source revision,
sanitized error code/correlation ID and affected resource ID in the protected
support record. Do not attach full state, plans, credentials or raw response logs.

| What you see | Next safe action and owner |
| --- | --- |
| Command not found, wrong folder, missing file or empty PowerShell variable | Repeat the tool/path checks and select the approved files. This is not a reason to provision Azure resources. |
| JSON parse or missing required input | Reopen the named input file, fix brackets/commas/placeholders and save. Do not edit the shared profile or enter ad-hoc values at a Terraform prompt. |
| Formatting check fails only for the HCL input file | Run `terraform fmt $workloadVarFile`, review that file and repeat the check. Do not bulk-reformat shared source to fix a local input-file issue. |
| `AuthorizationFailed`, PIM expiry or role-definition denial | Ask the identity/platform owner to check the actual principal, scope, role conditions and PIM activation. Do not broaden the test VM's roles. |
| Policy denial, missing quota or unsupported region/model | Ask the platform/model owner to resolve the approved configuration or allocation. Do not disable policy, select a random region or open public access. |
| Terraform state lock or backend warning | Contact the active state/pipeline owner. Do not force-unlock, migrate, replace or delete state as a shortcut. |
| Apply timeout or asynchronous operation still running | Inspect the resource's **Overview > JSON View** provisioning state and **Activity log** in Azure Portal. Coordinate with the operator; do not immediately rerun apply or recreate the resource. |
| Endpoint `Pending`, missing zone group or unexpected/public DNS result | Network/DNS owner completes approval, association or resolver/routing work. Repeat the read-only readiness checks before model calls or access closure. |
| HTTP `401` / `403` | Distinguish invalid authentication, missing invocation/key-read permission and an actual network denial. Check the same path's positive control; do not equate any `403` with private-only success. |
| HTTP `429`, no fresh telemetry, or `BLOCKED` acceptance | Review the model quota/limit or exact unfinished monitoring/test gate. Do not silently raise limits, retry billable calls indefinitely, enable payload capture or mark an unexecuted check passed. |
| `prevent_destroy`, replacement/deletion or central-network changes in the plan | Stop for a separately approved migration/change plan; do not remove the protection or switch ownership flags. |

Closing PowerShell loses variables such as `$workloadVarFile`,
`$networkOwnershipFile`, `$additionalVarFiles`, `$additionalInputArgs`,
`$endpointCompatibilityArgs`, `$networkArgs`, `$subscriptionId` and `$tenantId`; it
does not undo Azure changes. To resume:

1. Open the **same approved source directory**, confirm the commit and backend
   with the workload owner, and repeat the Azure-context check.
2. Re-select the **same saved workload and ownership files**. Do not copy
   templates over them. Restore all additional runtime inputs too.
3. Confirm the last completed stage from actual Azure state and the protected
   run record. For monitoring, choose the canonical procedure's
   [current-state row](docs/monitoring.md#choose-the-current-access-state) again.
   Never assume a new terminal means a new deployment or reuse the initial
   public override after an endpoint was closed.
4. Inspect any in-flight/failed operation and obtain the appropriate next-step
   approval. Create and review a **fresh** plan; do not reuse a stale plan.
5. If the optional VM was started, its named owner checks power state and
   [deallocates it](docs/private-connectivity.md#step-6-stop-the-vm-when-you-are-done)
   even when the previous session crashed.

## Understand the files before deploying

The read-only walkthrough has moved to [Understand the sample](docs/understand-the-sample.md).
These signposts preserve earlier links; they are not additional operator steps.

### Where do I edit, and where does Terraform run?

See [editors, runners and file languages](docs/understand-the-sample.md#where-do-i-edit-and-where-does-terraform-run).

### One configuration, not a sequence of scripts

See [one shared Terraform root](docs/understand-the-sample.md#one-configuration-not-a-sequence-of-scripts).

### Which files do I open or edit?

See [files to edit, select and leave unchanged](docs/understand-the-sample.md#which-files-do-i-open-or-edit).

### Replacement checklist for existing-network inputs

See the [seven-ID replacement checklist](docs/understand-the-sample.md#replacement-checklist-for-existing-network-inputs).

### Optional: highlight input placeholders in VS Code

See [optional scoped editor help](docs/understand-the-sample.md#optional-highlight-input-placeholders-in-vs-code).

### Why four subnet roles but only two endpoint keys?

See [three core subnet inputs and optional roles](docs/understand-the-sample.md#three-core-subnet-inputs).

### Follow one input through the code

See [the subnet-ID trace](docs/understand-the-sample.md#follow-one-input-through-the-code).

### Who manages DNS, and how do the input files get selected?

See [DNS ownership and input selection](docs/understand-the-sample.md#who-manages-dns-and-how-do-the-input-files-get-selected).

### Which commands and helper scripts matter?

See [helper purposes and side effects](docs/understand-the-sample.md#which-commands-and-helper-scripts-matter).

## Terraform implementation

The AzAPI/module distinction and preview contract notes are in
[Terraform implementation](docs/reference.md#terraform-implementation);
[resource lifecycle](docs/reference.md#resource-type-and-lifecycle) remains a
deployment prerequisite, not an optional repair step.
