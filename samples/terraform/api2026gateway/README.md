# AI Gateway: standalone Terraform entry

Deploy a standalone `Microsoft.ApiManagement/aigateways` gateway, Foundry model
deployments, routing policies, monitoring and agent-support infrastructure.
The gateway and model/key resources use **`2026-09-01-preview`**, without an
explicit gateway SKU override.

**Experimental, authenticated public endpoints; not a private-only deployment
or a migration.** Terraform does not build or run an agent application.

| Read | Purpose |
| --- | --- |
| **This page** | Choose your starting point, prepare inputs, deploy and check configuration. |
| [Architecture](architecture.md) | Understand the request flow, resources, identities and Terraform structure. |
| [Reference](reference.md) | Look up inputs, contracts, detailed safeguards and acceptance gates. |

The default bundle adds **token, monthly cost and request limits** to each
model registration. Model-call IP filtering is opt-in; backend safety uses
`Microsoft.DefaultV2`. Telemetry uses `payloadCapture = false`.
See [policy scope](reference.md#policies-and-backend-safety) for the limits of
these settings; configuration alone does not prove enforcement or delivery.

## Scenario coverage

Choose one starting point:

| Your starting point | What to keep or prepare |
| --- | --- |
| **New standalone lab** | New approved workload values and isolated state; copy the input template in step 2. |
| **Existing standalone workload** | Retain its contract, complete approved inputs, backend and authoritative state. Do not copy the new-lab template over them. Review changes through the same saved-plan procedure. |

The [legacy scenarios 01-04](../README.md#legacy-configuration-scenarios-01-04)
use a different Terraform root. They have **not** all been ported here, and their
runbook and profiles are not extra steps for this entry. This guide's default
new lab uses public endpoints; it does not migrate a legacy gateway.

### Backend-private verification

Optional private backend connectivity does **not** make gateway ingress private.
If private ingress or a disabled gateway public endpoint is mandatory, **stop**:
this entry does not implement that boundary. Before opting into a backend
foundation or disabling backend public access, review
[backend-private connectivity](reference.md#backend-private-connectivity) and
[network boundaries](reference.md#network-and-access-boundaries).

## 1. Confirm the deployment scope

- Obtain approval for the subscription, tenant, exact resource groups, regions,
  state boundary and **full resource footprint**, not only the gateway.
  The default uses three groups; a fresh-state single-group option is described
  in the [input reference](reference.md#inputs).
- Verify API access, model/version/SKU availability and quota for the selected
  subscription and regions. The checked-in profile is not availability evidence.
- Budget for model deployments, the agent account/project, Storage, **Premium**
  container registry and monitoring, plus any optional network/test-client
  resources. Policy cost limits are not a budget for the complete stack.
  Retain or clean up resources only under the approved lifecycle plan.
- Use Terraform `>= 1.11.0, < 2.0.0`, the committed AzAPI `2.13.0` lockfile,
  PowerShell 7 and an explicitly authenticated Azure CLI context for live checks.
  The deploying identity needs the approved resource and role-assignment rights.

Review the [deployment gates](reference.md#deployment-gates) and
[authentication choices](reference.md#caller-authentication). The default
runtime key is gateway-wide and not recommended for production. For an existing
workload, also review the [account capability](reference.md#api-contracts-and-lifecycle) and
[project monitoring connection](reference.md#project-monitoring-connection)
before planning; do not treat capability changes or connection cleanup as
implicit approval.

## 2. Select this root and prepare inputs

From the repository root, select the standalone entry in PowerShell:

```powershell
Set-Location .\samples\terraform\api2026gateway
```

**New lab only:** create a private working copy without overwriting existing inputs:

```powershell
$inputFile = "<new-private-input-file.tfvars>"
if (Test-Path -LiteralPath $inputFile) { throw "Do not overwrite existing approved inputs." }
Copy-Item -LiteralPath .\terraform.tfvars.example -Destination $inputFile
```

**Existing standalone workload:** set `$inputFile` to its retained, complete
approved input file instead. Do not initialize against a new or empty state.

| File | What you do |
| --- | --- |
| [terraform.tfvars.example](terraform.tfvars.example) | New-lab template. Edit only your private copy: set `subscription_id`, `environment_name`, `location` and `gateway_location` to approved values; replace every placeholder. |
| [model-profile.json](model-profile.json) | Read the default deployments, versions, capacities and aliases. Leave model maps unset to use it. |
| [model-routing.tfvars.example](model-routing.tfvars.example) | Optional complete-map example, not auto-loaded. If needed, put approved overrides in your complete input file. Maps **replace**, not merge with, defaults. |
| [variables.tf](variables.tf) / [input reference](reference.md#inputs) | Look up optional caller access, backend network/lab inputs, naming and rejected settings. Choose creation-time settings before the first deployment. |

Keep `model_allowed_client_cidrs` empty unless an allow list is approved. To
enable it, use the actual client/proxy egress IPv4/IPv6 CIDRs, not the commented
documentation ranges. It filters model calls; it does not create private ingress.

Terraform loads this directory's `.tf` files together, not in filename order.
Its `main.tf` calls the parent implementation as `module.gateway`; the resource
groups do not have separate states. Running from `..` instead selects the
**legacy root**. See [architecture](architecture.md) for the implementation map.

Approve state storage, access and isolation **before initialization**. This entry
declares no remote backend: without approved remote configuration it uses local
state. A new lab must not reuse another workload's backend key or `TF_DATA_DIR`,
or copy legacy state; an existing workload must retain its authoritative state.
A separate directory alone is not state isolation. Keep state, plans and private
inputs out of published output and source control; they can contain credentials
and connection strings. See [state and lifecycle](reference.md#state-and-lifecycle).

## 3. Run offline validation

```powershell
pwsh -NoLogo -NoProfile -File ..\scripts\Test-Offline.ps1
if ($LASTEXITCODE -ne 0) { throw "Offline validation failed; stop." }
```

This is the canonical offline command. Local checks and provider-mocked tests
are not live API, authentication, runtime, telemetry or quota acceptance.
Initialization may need access to download the already-locked provider; it does
not authorize a provider upgrade or an Azure deployment.

## 4. Initialize, save and review a plan

After confirming the approved backend/state setup, initialize this entry:

```powershell
terraform init -lockfile=readonly
if ($LASTEXITCODE -ne 0) { throw "Initialization failed; stop." }
```

Use the **complete** approved input file and a new private plan filename:

```powershell
$planFile = "<new-private-plan-file.tfplan>"
if (Test-Path -LiteralPath $planFile) { throw "Use a new plan filename." }
terraform plan -var-file="$inputFile" -out="$planFile"
if ($LASTEXITCODE -ne 0) { throw "Planning failed; do not apply." }
terraform show "$planFile"
if ($LASTEXITCODE -ne 0) { throw "Plan display failed; do not apply." }
```

Review the exact groups, model capacities, identities, public endpoints,
monitoring, optional resources and every replacement/deletion. Keep the output
private and obtain approval for **this saved plan**. A changed input, source or
state requires a fresh plan and review, not a targeted shortcut.

## 5. Apply only the approved saved plan

In the same entry directory and approved state/context:

```powershell
terraform apply "$planFile"
if ($LASTEXITCODE -ne 0) { throw "Apply failed; stop and review before continuing." }
```

A saved-plan apply has **no interactive approval prompt**. Run it only after
approval; do not replace it with an unreviewed apply. Gateway deletion protection
remains enabled. Backend subnet changes are replacement-sensitive, not a way to
convert an existing public gateway to private ingress.

## 6. Verify the deployed configuration

Read only the outputs needed for the next check:

```powershell
terraform output resource_groups
terraform output gateway_endpoint
terraform output gateway_api_versions
```

With the already-authenticated account selected, pass the **approved exact
group names**, subscription and tenant to the configuration checker. The example
uses the default three groups; for an approved single-group lab, supply only its
exact group name **and add `-SingleResourceGroup`**. For the owned private-backend
lab, also add `-PrivateLab -ExpectedBackendPublicNetworkAccess Disabled`.
Apply any separately approved external NSG option from the references below.

```powershell
& ..\scripts\Test-Api2026Deployment.ps1 `
  -TerraformDirectory (Get-Location).Path `
  -SubscriptionId "<approved-subscription-guid>" `
  -TenantId "<approved-tenant-guid>" `
  -AllowedResourceGroups @("<gateway-group>", "<models-group>", "<agents-group>")
```

The checker does not deploy or run inference. It checks selected Terraform/ARM
configuration, keeps raw state in memory and returns a sanitized report.
Optional `-ReportPath` must name a **new** file in an existing private directory.
Failure is terminating/nonzero, not an acceptance pass.

Use these focused references when they apply; do not relax the checker:

- [Backend-private connectivity](reference.md#backend-private-connectivity):
  required network preparation and explicit backend verification arguments.
- [External private-endpoint NSG](reference.md#external-private-endpoint-nsg):
  exact approved attachment and strict exception checks.
- [Live readback projections](reference.md#live-readback-projections):
  narrowly accepted service projections, not permission to ignore mismatches.
- [Project monitoring connection](reference.md#project-monitoring-connection):
  project-local ownership, sharing checks and separately approved correction.

## 7. Record acceptance separately

`configurationStatus = PASS` still means `overallStatus = INCOMPLETE`.
For separately approved inference, follow the
[bounded runtime probe](reference.md#bounded-runtime-probe), with a token cap and
timeout. Record runtime, policy/failover behavior, telemetry delivery,
idempotence, portal and agent-runtime evidence as separate
[acceptance gates](reference.md#monitoring-and-acceptance). Private connectivity
needs its own evidence; gateway private ingress is not implemented. Do not infer
customer readiness from a clean plan, offline tests or a configuration-only PASS.
