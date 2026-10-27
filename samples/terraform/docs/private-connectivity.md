# Private-only path

This is the private alternative to the [public endpoint path](../README.md#public-endpoint-path),
not an extra step after its public plan/apply. It uses the gateway resource type
declared by this sample; see [resource type and lifecycle](reference.md#resource-type-and-lifecycle).

**Goal:** prove this route works with gateway and model public access disabled:

```text
Private client -> gateway private endpoint -> private model endpoint
```

**Provisioning stages, one private end state:**

| Setting | `private-connectivity` (intermediate stage only) | `private-only` (required end state) |
| --- | --- | --- |
| `enable_private_networking` | `true` | `true` |
| `gateway_private_endpoint_manual_approval` | `true` (Pending, then explicitly approve) | `true` |
| `gateway_public_network_access` | `Enabled` | `Disabled` after private-route verification |
| `models_public_network_access` | `Disabled` after step 4 | `Disabled` |

The profiles express desired configuration, not runtime proof. Public and
Private-only are the two deployment paths; the intermediate profile is retained
for staged provisioning and compatibility. Keep `private-only` last on every
final-state plan, including drift/monitoring changes; it overrides earlier
var-files and `terraform.tfvars`. Also retain the selected
[network-ownership profile](../deployment.md#network-foundation-create-or-existing)
before it: create a sample foundation, or reuse approved network/DNS IDs.
Neither ownership profile changes public access. Reusing the intermediate
profile can plan to reopen a disabled gateway.

The gateway endpoint uses a manual request followed by an explicit APIM
connection approval. With workload-managed DNS, Terraform waits for approval
before creating its DNS zone group. With platform-managed DNS, the central
process owns that association; Terraform does not wait for it.
Approval first verifies that the service-created connection belongs to
the expected endpoint. An explicit PUT action preserves the required body `id`;
the legacy API rejects ordinary update-resource requests that omit this field.
Already-approved connections are read with GET instead: the legacy API also
rejects redundant approval. After a newly Pending connection is approved, run
a second plan/apply to record this read-only GET state before the final drift
check. This does not recreate the endpoint or change its approval.
This avoids an observed legacy auto-approval failure:
`PrivateConnectionNotFound`, where Network expects a generated connection name
but APIM stores the caller-supplied name. `Approved` alone is not sufficient:
wait for the asynchronous operation, both provisioning states and private DNS,
then prove inference from the VNet.

**Existing deployments:** this profile now selects the separately named
`-gateway-manual-pe`. Switching the flag replaces the gateway endpoint, not the
gateway service or the model endpoint. Review the plan before migrating. To
retain a healthy automatic endpoint, override
`-var=gateway_private_endpoint_manual_approval=false` after the profile on every
plan. Never import a new endpoint over the old state without first preserving
state and accounting for the old cloud resource.

**Cleanup caveat:** the legacy service can retain an APIM connection record
after its failed Network endpoint and NIC have been deleted. In the observed
repair, deleting that orphan or first rejecting it returned an asynchronous
`UpdateApiServiceFailed`; the approved replacement kept working. Follow the
operation's polling URL: an initial `202` is not successful cleanup. Verify the
old endpoint/NIC are absent and the replacement still passes private inference.
Record the residual APIM reference rather than repeatedly retrying or rebuilding
the gateway. A zero-drift Terraform plan does not prove this unmanaged reference
has disappeared.

See the [AI Gateway private networking guide](https://learn.microsoft.com/azure/api-management/ai-gateway-configure-private-networking)
for the Pending/Approve sequence.

> **October 27, 2026: original-SKU creation and staged Terraform closure passed**
> in an isolated Sweden Central rehearsal with independently owned network/DNS.
> Both private aliases, auth/public-network boundaries, telemetry, firewall
> traffic and four no-change plans passed. This does not prove private-from-
> first-create or another customer's environment. The October 25 portal/private-
> agent proof is separate; no hosted-agent application ran in the new rehearsal.
> See [evidence and verification boundaries](reference.md#private-only-gateway-ingress-status).
>
> Hosted-agent networking and proof of agent execution remain outside this profile.
> A separate opt-in [private hosted-agent extension](private-hosted-agent.md)
> configures the new agent account at creation. Its separately deployed
> application passed a live test; the extension is not enabled by this profile.

**Already have a working private deployment?** Go to
[existing private deployments](#existing-private-deployments); do not repeat
staging or re-enable gateway/model public access.

## Prerequisites

Complete the [guided prerequisites](../deployment.md#prerequisites),
[input/state selection](../deployment.md#inputs-and-state) and
[platform handoff](../deployment.md#platform-handoff-before-a-plan).
Use PowerShell 7 in the approved `samples\terraform` directory. Retain the
workload's state/backend; the central network keeps its own owner/state.
Do not run the public-path plan/apply. Additional requirements:

- Complete the [two-stage OTLP destination setup](monitoring.md) before planning
  the exporter. Keep the private profile on those plans too; readiness discovery
  must not re-enable a private gateway/model backend or rebuild the gateway.
- `Microsoft.Network` registered
- For the test VM: `Microsoft.Compute`, regional VM quota, and permission to use VM Run Command

Keep the variables selected in [Compose the inputs](../deployment.md#compose-the-inputs).
The following checks their presence; it deliberately does **not** reset an
existing-network selection to `create`:

```powershell
foreach ($name in @('customerVarFile', 'networkOwnershipFile', 'additionalInputArgs',
                    'endpointCompatibilityArgs', 'subscriptionId')) {
    if (-not (Get-Variable -Name $name -ErrorAction SilentlyContinue)) {
        throw "Missing $name. Restore the main guide's complete input selection."
    }
}
```

For a new terminal, follow the main guide's
[resume instructions](../deployment.md#if-something-fails-or-you-open-a-new-terminal).
Do not replace saved customer files with templates.

`create` is the default and preserves the sample's names, Terraform addresses and
network ranges. It creates only the sample gateway network/DNS foundation, not a
corporate hub, firewall, resolver or landing zone. Network and DNS are separate
logical concerns, but this implementation supports only paired ownership:
create both, or reuse both; no create-network/external-DNS hybrid.

### Existing network prerequisites

Set `private_network_mode = "existing"` with `enable_private_networking = true`.
`existing_private_network` is required in this mode and must remain `null` in
`create` mode. Missing required inputs fail; no fallback foundation is created.
The deployment reads subnets and their parent VNets through AzAPI for actual
location, **IPv4** CIDRs, delegations and the gateway subnet's NSG attachment.
It does not infer geography from an ARM ID or use the demo `/16` for existing subnets.

| `existing_private_network` field | Required input |
| --- | --- |
| `gateway_subnet_id` | Gateway integration subnet ARM ID (string). The subnet must be delegated to `Microsoft.Web/serverFarms`, with at least a `/27` IPv4 range and an attached network security group (NSG); its parent VNet must be in `gateway_location`. |
| `endpoint_subnet_ids` | Map of service name to approved subnet ARM ID, all in the workload `subscription_id`. Different resource groups, VNets and regions are allowed. `gateway` and `models` are mandatory; add `storage` for `enable_storage_private_endpoint`, and `agents` plus `registry` for `enable_private_hosted_agent`. |
| `private_dns_zone_ids` | Map of logical key to central zone ARM ID, as listed below; zones may be in another subscription. Required even when the platform owns DNS zone groups. |
| `agent_subnet_id` | Required only when `enable_private_hosted_agent = true`: a separate integration subnet at least `/27`, wholly within RFC1918 IPv4, delegated to `Microsoft.App/environments`, with its VNet in the agent region (`location`). |
| `client_subnet_id` | Required only when `enable_private_test_client = true`: an explicitly approved subnet in workload `subscription_id` for the optional probe VM/NIC. Their location follows the actual VNet. Existing private clients need no sample VM or client-subnet input. |

RFC1918-only agent address space (`10.0.0.0/8`, `172.16.0.0/12`,
`192.168.0.0/16`) is **this sample's supported subset**, not a universal Foundry
restriction. The [Foundry networking options](https://learn.microsoft.com/azure/foundry/agents/concepts/networking-options)
document the `/27` minimum and `Microsoft.App/environments` delegation and also
discuss CGNAT address space, which this sample does not currently accept.

#### Confirm the gateway subnet's network security group

**Who:** the network/platform owner. **Where:** Azure Portal, in the approved
subscription and VNet. An NSG is the subnet's traffic-rule resource. Having an
NSG somewhere in the resource group is not enough: it must be attached to the
exact gateway integration subnet.

1. Open **Virtual networks**, then the VNet containing `gateway_subnet_id`.
   Check its subscription/resource group against the copied ID.
2. Open **Settings > Subnets** and select that exact integration subnet, not a
   private-endpoint subnet.
3. Find **Network security group**. It must show the approved NSG, not **None**.
   In the VNet's **JSON View**, the same subnet must have
   `properties.networkSecurityGroup.id`.
4. If it is missing, **stop**. Ask the platform owner to attach the approved
   NSG through the existing network Terraform/Terragrunt process. Do not select
   an arbitrary NSG, change its rules in the portal, switch to `create`, or let
   the gateway deployment take ownership of central networking.
5. Have the owner check effective outbound rules together with UDRs/firewall:
   required DNS to the approved resolver, HTTPS to the model/backend endpoints,
   Azure Key Vault, Storage and the configured monitoring destinations must work.
   The sample's create-mode NSG includes outbound TCP 443 rules for
   `AzureKeyVault` and `Storage`; reuse mode does not add these to a customer NSG.
   NSG presence alone does not prove that the private route or egress is usable.
6. After the platform change finishes, repeat step 3 and rerun the full gateway
   plan. Keep the same approved subnet ID. There is **no extra NSG input** to
   copy into the workload's configuration.

**Expected:** the existing-subnet check passes without creating or changing an
NSG in workload state. Missing attachment now stops the full plan with a
platform-owner action message instead of the later Azure
`NetworkSecurityGroupNotFound` creation error observed in the live rehearsal.
Do not open public inbound ports or change the gateway SKU to work around it.
The [outbound-integration prerequisites](https://learn.microsoft.com/azure/api-management/integrate-vnet-outbound#network-security-group)
also describe NSG and Key Vault requirements for v2 tiers; the rehearsal error
is the direct evidence for this sample's unchanged legacy AIGateway resource.

| DNS map key | Required zone name | When required |
| --- | --- | --- |
| `gateway` | `privatelink.azure-api.net` | Always |
| `cognitiveservices` | `privatelink.cognitiveservices.azure.com` | Always |
| `openai` | `privatelink.openai.azure.com` | Always |
| `services` | `privatelink.services.ai.azure.com` | Always |
| `storage` | `privatelink.blob.core.windows.net` | Storage private endpoint enabled |
| `registry` | `privatelink.azurecr.io` | Private hosted agent enabled |

Endpoint subnets must be separate from delegated integration subnets; never put
a private endpoint in the gateway or agent integration subnet. Services may use
different approved endpoint subnets and VNets, including different locations.
Each endpoint and the optional VM use their own subnet's actual VNet location;
only gateway/agent integration must match the respective service region.
Check available addresses, endpoint approval and the approved NSG/UDR/firewall
paths for every caller and backend dependency before deployment.

New private endpoints remain in the workload resource group and
`subscription_id`. Azure requires each private endpoint to be in the
[same subscription and region as its VNet](https://learn.microsoft.com/azure/private-link/private-endpoint-overview#private-endpoint-properties),
so endpoint subnet IDs from another subscription fail validation; the endpoint
location follows its supplied VNet. Cross-subscription endpoint placement or
ownership is a separate extension, not implemented here. This does not prevent
using central DNS zones in another subscription.

For the optional test VM, Azure requires the
[NIC and VNet to share subscription/location, and the VM to match its NIC](https://learn.microsoft.com/azure/virtual-network/virtual-network-network-interface#create-a-network-interface).
The sample keeps VM/NIC ownership in the workload subscription, so enabled
`client_subnet_id` must also belong to `subscription_id`; its VNet supplies the
actual location. Changing an existing client subnet is a separate migration,
not an automatic VM/NIC relocation.

The customer keeps ownership of subnets, VNet settings, NSGs, UDRs, firewall,
resolver, private DNS zones and links. Existing mode never modifies central
subnet policies or assumes each spoke has a direct DNS-zone link. Validate the
actual central resolver/forwarding path from every intended client.

The deployment identity needs scoped read access to the supplied subnets/VNets,
subnet join permissions, and permission to create/manage the workload's new
private endpoints and approve the service connections. When the workload owns
zone groups, also authorize the endpoint zone-group operations and association
to the **specific supplied DNS zones**. Read/join alone does not grant these
permissions. Coordinate cross-subscription central DNS access with the platform team;
do not grant Owner or broad subscription access to bypass missing permissions.

Choose **one** DNS zone-group owner:

- `private_dns_zone_group_management = "workload"` (default) creates the new
  endpoints' zone-group associations to supplied zones with those scoped
  permissions. It does not take ownership of central zones or links.
- `"platform"` is allowed only in existing mode. Terraform creates the endpoints
  but omits their zone groups; policy/central deployment must complete the
  associations and records. Terraform does not manage central records/links or
  wait for policy. Finish platform DNS integration **before** private calls,
  agent use or closure of public access.

In either case, verify approved/provisioned endpoints, service-specific private
resolution and real runtime connectivity. Terraform success is not DNS or
resolver-readiness evidence. Existing mode does not import pre-existing private
endpoints, application/model resources or resource groups. Use each resource's
authoritative owner and state, not a second import.

The acceptance runner requires delivered endpoint `privateDnsZoneGroups` with
the **exact expected zone IDs**. In platform mode any group name is valid,
regardless of Terraform ownership. Missing bindings fail: manually maintained
DNS records alone, even if they resolve, are not certified by this runner.
Gateway/model/optional-storage DNS checks and private inference/authentication
proof remain required. Hosted-agent/registry runtime and public-network rejection
need separate evidence.

### Test-client permissions

The Terraform deployment identity and the VM's managed identity have different
jobs. Creating role assignments alone does **not** authorize creating a custom
role definition. The table below describes the **optional sample-managed VM**.
For an existing, platform-owned client, its owner manages the client's identity
and equivalent gateway-scoped runtime permission separately. Do not enable the
sample VM or import that client's resources just to run these checks.

| Identity | Required permission and scope |
| --- | --- |
| Terraform deployment identity | `Microsoft.Authorization/roleDefinitions/read`, `write`, and `delete` to manage the custom role through its lifecycle. The definition is addressed under the subscription, but its only `assignableScopes` entry is the gateway resource group. The identity must be authorized to manage definitions for that assignable scope. |
| Terraform deployment identity | `Microsoft.Authorization/roleAssignments/read`, `write`, and `delete` at the gateway resource for the VM's binding, in addition to the six service bindings and the exact OTLP DCR publisher binding. Respect managed-group deny assignments. |
| Test operator | Read the VM and its instance view; `Microsoft.Compute/virtualMachines/runCommand/action` to run the probe, `start/action` and `deallocate/action` for its power lifecycle, scoped to the test VM. |
| Test VM managed identity | Only `Microsoft.ApiManagement/service/apiKeys/listSecrets/action`, assigned **on the gateway resource**, not the subscription. Terraform creates this role/binding. |

Ask your subscription administrator to verify effective permissions, assignment
conditions and deny assignments **before enabling the VM**. Contributor alone
cannot manage RBAC, and Role Based Access Control Administrator does not by itself
grant custom role-definition management. Do not solve this by granting Owner to
the VM or broadening its key-reader role. See Microsoft's
[custom-role permissions](https://learn.microsoft.com/azure/role-based-access-control/custom-roles#who-can-create-delete-update-or-view-a-custom-role).
Deletion rights are needed for cleanup too; do not remove a role definition while
assignments still reference it.

If these permissions cannot be granted, keep `enable_private_test_client = false`
and use an approved existing private client with its own approved authentication.
This avoids the custom test-VM role, not the six core service roles or DCR publishing role.
It does not remove the need for the existing client's own runtime authorization.
The deployment host retains Terraform/backend and infrastructure-read access;
the client needs neither that state nor those deployment permissions.

## Step 1: Choose your test client

**Who:** the workload/test owner, with the network owner. Choose one client
before the full infrastructure plan:

| Choice | Preparation |
| --- | --- |
| Existing approved private client | Use a Windows machine/worker with the actual private DNS and route, PowerShell 7, Azure CLI, and its own approved runtime identity. No Terraform/backend access is required. Leave the sample VM disabled for a new workload; no client-subnet ID is needed. Follow [the nonsecret handoff and existing-client commands](#test-from-an-existing-private-client). |
| Optional sample VM | Follow the key/permission steps below, and supply the client subnet in existing mode. The helper uses Azure VM Run Command; no public IP or inbound SSH is needed. |

Do not copy state, full output dumps, personal sign-in tokens, keys or passwords
to a test machine. The two-terminal procedure below transfers only allowlisted
nonsecret metadata. Selecting a different test client does not authorize deleting
a VM already managed in state.

### Optional policy-restricted Blob storage

If Azure Policy disables storage public access, align the input with that
restriction rather than repeatedly applying an `Enabled` value:

```hcl
storage_public_network_access   = "Disabled"
enable_storage_private_endpoint = true
```

Together with the private profile this adds one `blob` private endpoint.
Create mode also adds the `privatelink.blob.core.windows.net` zone and VNet link.
Existing mode requires `endpoint_subnet_ids.storage` and
`private_dns_zone_ids.storage`, leaving the central zone/link unchanged.
The selected DNS owner supplies the zone group. Existing gateway/model endpoints
are retained. Review the complete plan before applying. The new endpoint needs
approval and private DNS just like the other services.

When the optional VM is enabled, it also receives **Storage Blob Data Reader on
this storage account only**. The probe verifies private DNS and HTTPS and lists
at most one container using the VM's managed identity. It does not print
container names, create data, retrieve storage keys or grant write access.
The acceptance runner checks the exact identity/scope, disabled public access,
endpoint/DNS wiring and real successful storage operation.

This proves the **VM-to-Blob** path, not hosted-agent storage access. Hosted-agent
runtimes require their own supported VNet integration if their application uses
this storage connection. A basic model-only agent does not exercise that path.
No File, Queue, Table or DFS endpoint is created; add only services a real
consumer needs. See [Azure Storage private endpoints](https://learn.microsoft.com/azure/storage/common/storage-private-endpoints).

Turning the option off can delete its endpoint and test role and can propose
removal of sample-managed DNS resources; review cleanup separately.
DNS zones have no blanket `prevent_destroy` guard. Reused central zones/links are not deleted.
This feature never modifies or exempts Azure Policy.

### Private gateway test VM

Skip this subsection if using an existing private client.
**Who:** the workload operator, after approval of the extra permissions and VM
cost. First obtain an approved OpenSSH **public** key. If you already have one,
open only its `.pub` file and copy its complete single line; do not overwrite
or display the corresponding private file.

If a new dedicated key is required and company policy permits local generation:

```powershell
Get-Command ssh-keygen -ErrorAction Stop
$keyDirectory = Join-Path $HOME '.ssh'
$keyPath = Join-Path $keyDirectory 'aigateway-test'
if ((Test-Path -LiteralPath $keyPath) -or (Test-Path -LiteralPath "$keyPath.pub")) {
    throw 'This key name already exists. Use the approved public key or choose a new name.'
}
if (-not (Test-Path -LiteralPath $keyDirectory)) {
    $null = New-Item -ItemType Directory -Path $keyDirectory
}
ssh-keygen -t ed25519 -f $keyPath -C 'aigateway-test'
if ($LASTEXITCODE -ne 0) { throw 'Key generation failed.' }
Get-Content -LiteralPath "$keyPath.pub"
```

Follow the organization's passphrase policy at the prompt. If `ssh-keygen` is
missing, ask IT to provide the approved OpenSSH tooling or public key; do not
lower security settings. **Expected:** one line starting `ssh-ed25519`.
Keep the private file protected, outside the repository.

Open the **approved base input file** (`$customerVarFile`), add or update these
HCL settings with the public line, and save. Do not paste HCL into PowerShell:

```hcl
enable_private_test_client         = true
private_test_client_ssh_public_key = "ssh-ed25519 <your-public-key>"
```

- Use a **public** key only. Never paste a private key or password.
- The VM is billable and has no public IP. In create mode the sample NSG denies inbound traffic; existing mode retains customer NSGs/UDRs. The probe uses Run Command, not SSH.
- Existing mode also requires `existing_private_network.client_subnet_id` and approved VM agent/ARM egress; Terraform does not open central firewall or subnet rules.
- `Test-PrivateGateway.ps1` requires this applied VM. The existing-client route below does not call it.

<a id="step-2-create-networking-with-models-temporarily-public"></a>

## Step 2: Prepare private connectivity with models temporarily public

Use this stage when adding private networking to an existing legacy gateway
whose model backend is still public. It is not the final posture.
Temporary public access must be explicitly permitted.
**Do not run it on an already-disabled gateway or backend.** A new environment
that prohibits even temporary public access needs a separately validated creation
sequence; this staged guide is not that proof.

```powershell
$networkProfile = 'private-connectivity'
terraform plan -input=false "-var-file=$customerVarFile" @additionalInputArgs `
    "-var-file=$networkOwnershipFile" "-var-file=profiles\$networkProfile.tfvars.json" `
    @endpointCompatibilityArgs "-var=models_public_network_access=Enabled" `
    "-out=private-connectivity-stage1.tfplan"
if ($LASTEXITCODE -ne 0) { throw 'Private staging plan failed.' }
terraform show private-connectivity-stage1.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the private staging plan.' }
```

Review the plan: gateway and model public access are both enabled, new private
endpoints and the VM (if enabled) are created. Create mode also creates the sample
foundation; existing mode must show no changes to central subnet/VNet/zone/link
resources.
Do not apply unexpected replacements or permission expansion.

```powershell
terraform apply "private-connectivity-stage1.tfplan"
if ($LASTEXITCODE -ne 0) { throw 'Private staging apply failed; stop.' }
```

## Step 3: Check the private route

### Endpoint and DNS readiness

First confirm endpoint approval/provisioning and DNS readiness with the selected
zone-group owner. In platform mode an apply can finish before policy/central DNS
does; do not run the probe or an agent until that integration is complete.

**Who/where:** the workload and network/DNS owners, using the approved workload
outputs and Azure Portal. These reads do not change Azure:

```powershell
terraform output -raw resource_group_name
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the workload group.' }
terraform output -json private_endpoint_ids
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the endpoint IDs.' }
terraform output -json private_network_configuration
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the selected network metadata.' }
```

1. In Azure Portal, open the returned workload resource group. Open each private
   endpoint whose **Overview > JSON View** `id` matches the output; do not choose
   a similarly named old/failed endpoint.
2. Verify its provisioning state is **Succeeded** and its connection is
   **Approved**. In JSON, the connection is in `privateLinkServiceConnections`
   or `manualPrivateLinkServiceConnections`; it must point to the intended
   gateway/model/other service, not another resource.
3. Open the target service's private-endpoint connections and confirm the same
   endpoint ID is **Approved**, with successful provisioning there too.
   `Pending`, `Rejected`, `Disconnected` or `Failed` means stop and contact
   the approval/network owner. Terraform's gateway approval is not permission
   to approve unrelated requests manually.
4. Open the endpoint's **DNS configuration** and associated **Network interface**.
   Record its actual DNS names and private IP addresses in the protected run
   record. Check the DNS zone groups against `private_network_configuration`:
   the group name may differ in platform mode, but the expected zone IDs must
   match. The DNS owner can confirm cross-subscription associations.
5. In platform mode, wait for the central owner to confirm completion. An apply
   finishing before central policy does is not DNS readiness. Do not create a
   second zone/group while waiting.
6. Now use **one** client procedure below to test the resolver actually used by
   that client. An IP that merely starts with `10.` is not enough; compare it
   with the selected service's endpoint. Do not add a hosts-file override.

**Expected:** all required endpoints and associations are ready. Manual DNS
records without zone groups are outside the automated runner's certification
contract. Optional Storage and agent/registry paths need their own checks too.

**Model prerequisite:** all aliases must support the probe's OpenAI Chat
Completions request, including `max_tokens` and `temperature`. The sample's
`gpt-4.1` and `gpt-4.1-mini` configuration is the reference. Responses-only,
embeddings, image, or other API formats need their own test. The probe rejects
incompatible API metadata before DNS/key retrieval; it does not interpret that
rejection as a networking failure. See [probe compatibility](reference.md#probe-compatibility).

### Test from an existing private client

Use **two PowerShell 7 terminals**, even if one approved machine can perform
both jobs. Keep them open; do not mix their variables.

| Terminal | Where and what it does |
| --- | --- |
| A - deployment | The existing deployment host and authoritative Terraform/Terragrunt unit. Reads outputs and Azure configuration, prepares metadata, closes access, checks roles/telemetry and runs the final plan. It does not need the private inference route. |
| B - private client | The approved Windows private client, using its own approved identity. Resolves DNS and makes runtime requests. It does not run Terraform or read the backend. |

1. Finish the endpoint/zone-group checks immediately above on **A**.
2. Ask the platform owner to prepare **B** with the real resolver/route and its
   own approved sign-in. API-key tests require only the gateway-scoped
   `Microsoft.ApiManagement/service/apiKeys/listSecrets/action` runtime grant.
   The sample does not create that grant for an externally managed client.
   Keep ARM/sign-in egress available; do not transfer the deployment identity.
3. Agree a restricted evidence folder **outside the checkout** on each host
   and an approved transfer channel. These IDs/IPs are not credentials, but
   still belong in a restricted customer run record.
4. On **A**, restore the approved context and run the export below. For
   Terragrunt, replace only `terraform output -json` with
   `terragrunt run --log-level error --tf-forward-stdout -- output -json`
   **inside the actual workload unit**. Do not initialize a second backend.

This uses `private_endpoint_ids`, not the VM-only `private_probe_configuration`.
It reads full outputs into local memory, but writes **only the named subset**:

```powershell
$privateOutputJson = terraform output -json
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the workload outputs.' }
$privateOutputs = $privateOutputJson | ConvertFrom-Json
$privateOutputJson = $null
$gatewayResourceId = [string]$privateOutputs.gateway_id.value
$modelsResourceId = [string]$privateOutputs.foundry_models_id.value
$gatewayAccess = az rest --subscription $subscriptionId --method get `
    --url "https://management.azure.com${gatewayResourceId}?api-version=2025-09-01-preview" `
    --query properties.publicNetworkAccess --output tsv --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Cannot read gateway access posture.' }
$modelJson = az rest --subscription $subscriptionId --method get `
    --url "https://management.azure.com${modelsResourceId}?api-version=2025-04-01-preview" `
    --query '{endpoint:properties.endpoint,access:properties.publicNetworkAccess}' `
    --output json --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the model endpoint/access posture.' }
$modelMetadata = $modelJson | ConvertFrom-Json
$stage = if ($gatewayAccess -eq 'Enabled' -and $modelMetadata.access -eq 'Enabled') {
    'bootstrap'
} elseif ($gatewayAccess -eq 'Enabled' -and $modelMetadata.access -eq 'Disabled') {
    'models-private'
} elseif ($gatewayAccess -eq 'Disabled' -and $modelMetadata.access -eq 'Disabled') {
    'private-only'
} else { throw 'Unexpected public-access combination; review before testing.' }
$dnsTargets = @(
    @{ name = 'gateway'; url = [string]$privateOutputs.gateway_endpoint.value },
    @{ name = 'models'; url = [string]$modelMetadata.endpoint }
)
if ($privateOutputs.private_endpoint_ids.value.storage) {
    $storageResourceId = "/subscriptions/$subscriptionId/resourceGroups/$($privateOutputs.resource_groups.value.agents)/providers/Microsoft.Storage/storageAccounts/$($privateOutputs.storage_account_name.value)"
    $blobUrl = az rest --subscription $subscriptionId --method get `
        --url "https://management.azure.com${storageResourceId}?api-version=2024-01-01" `
        --query properties.primaryEndpoints.blob --output tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or -not $blobUrl) { throw 'Cannot read the Blob endpoint.' }
    $dnsTargets += @{ name = 'storage'; url = [string]$blobUrl }
}
foreach ($target in $dnsTargets) {
    $endpointId = [string]$privateOutputs.private_endpoint_ids.value.($target.name)
    if (-not $endpointId) { throw "Missing endpoint ID: $($target.name)" }
    $nicJson = az network private-endpoint show --subscription $subscriptionId `
        --ids $endpointId --query 'networkInterfaces[].id' --output json --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read endpoint interfaces.' }
    $nicIds = @($nicJson | ConvertFrom-Json)
    $target.expectedIps = @(
        foreach ($nicId in $nicIds) {
            $ipJson = az network nic show --subscription $subscriptionId --ids $nicId `
                --query 'ipConfigurations[].privateIPAddress' --output json --only-show-errors
            if ($LASTEXITCODE -ne 0) { throw 'Cannot read endpoint private IPs.' }
            $ipJson | ConvertFrom-Json
        }
    )
    if ($target.expectedIps.Count -eq 0) { throw 'The selected endpoint has no private IP.' }
    $target.endpointId = $endpointId
}
$clientHandoff = [ordered]@{
    schemaVersion = 1
    runId = [guid]::NewGuid().ToString('N')
    capturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    stage = $stage
    subscriptionId = $subscriptionId
    tenantId = $tenantId
    dnsTargets = $dnsTargets
    outputs = @{
        gateway_id = @{ value = $gatewayResourceId }
        gateway_endpoint = @{ value = [string]$privateOutputs.gateway_endpoint.value }
        gateway_api_key_id = @{ value = [string]$privateOutputs.gateway_api_key_id.value }
        model_deployment_ids = @{ value = $privateOutputs.model_deployment_ids.value }
        model_api_configuration = @{ value = $privateOutputs.model_api_configuration.value }
    }
}
$evidenceDirectory = Read-Host 'Full path to the existing restricted evidence folder outside the checkout'
if (-not [IO.Path]::IsPathFullyQualified($evidenceDirectory) -or
    -not (Test-Path -LiteralPath $evidenceDirectory -PathType Container)) {
    throw 'Use an existing, approved restricted folder with an absolute path.'
}
$handoffFile = Join-Path $evidenceDirectory "private-client-$($clientHandoff.runId).json"
$clientHandoff | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $handoffFile -Encoding utf8NoBOM
Get-FileHash -LiteralPath $handoffFile -Algorithm SHA256
```

5. On **A**, inspect **only that exported file**. Confirm the selected resource
   IDs, hostnames, endpoint NIC IPs and stage. Transfer the file through the
   approved channel and communicate its SHA256 separately. Never send raw state,
   `.terraform`, a complete output dump, auth caches, keys, tokens or passwords.
6. On **B**, open PowerShell 7. The platform owner must already have signed in
   the approved client identity. Run this import and DNS check, not acceptance
   Steps 1-3 or Terraform commands:

```powershell
$ErrorActionPreference = 'Stop'
$handoffFile = Read-Host 'Full path to the approved transferred metadata file'
$expectedHash = (Read-Host 'SHA256 confirmed by the deployment owner').Trim()
if ((Get-FileHash -LiteralPath $handoffFile -Algorithm SHA256).Hash -ine $expectedHash) {
    throw 'Metadata hash mismatch. Obtain the correct file; do not bypass the check.'
}
$clientHandoff = Get-Content -LiteralPath $handoffFile -Raw | ConvertFrom-Json
$expectedStage = Read-Host 'Expected stage: bootstrap, models-private, or private-only'
$age = [DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse($clientHandoff.capturedAtUtc)
if ($clientHandoff.schemaVersion -ne 1 -or
    $expectedStage -notin @('bootstrap', 'models-private', 'private-only') -or
    $clientHandoff.stage -cne $expectedStage -or $age.TotalMinutes -gt 30 -or $age.TotalMinutes -lt -1) {
    throw 'Wrong-stage or stale metadata. Ask A for a fresh export after the latest apply.'
}
$subscription = [string]$clientHandoff.subscriptionId
$tenant = [string]$clientHandoff.tenantId
$accountJson = az account show --subscription $subscription --output json --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'The client identity is not signed into the approved subscription.' }
$account = $accountJson | ConvertFrom-Json
if ($account.id -ine $subscription -or $account.tenantId -ine $tenant) {
    throw 'Client subscription/tenant mismatch; do not switch identities automatically.'
}
$o = $clientHandoff.outputs
$gatewayId = [string]$o.gateway_id.value
if (-not $gatewayId.StartsWith("/subscriptions/$subscription/", [StringComparison]::OrdinalIgnoreCase) -or
    $o.gateway_api_key_id.value -notmatch ('^' + [regex]::Escape($gatewayId) + '/apiKeys/[^/?#]+$')) {
    throw 'Gateway/key resource scope mismatch.'
}
$dnsEvidence = @()
foreach ($target in $clientHandoff.dnsTargets) {
    $uri = [uri]$target.url
    if ($uri.Scheme -cne 'https' -or $uri.Port -ne 443 -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'Unexpected service URL in the approved metadata.'
    }
    $resolvedIps = @(Resolve-DnsName -Name $uri.DnsSafeHost -Type A -DnsOnly -NoHostsFile -ErrorAction Stop |
        Where-Object Type -eq 'A' | Select-Object -ExpandProperty IPAddress -Unique)
    if (@($target.expectedIps).Count -eq 0 -or $resolvedIps.Count -eq 0 -or
        @($resolvedIps | Where-Object { $_ -notin @($target.expectedIps) }).Count) {
        throw "DNS does not match the selected endpoint: $($target.name)"
    }
    $dnsEvidence += [pscustomobject]@{
        name = $target.name; hostname = $uri.DnsSafeHost; addresses = $resolvedIps
    }
    "$($target.name): $($uri.DnsSafeHost) -> $($resolvedIps -join ', ') (endpoint IP match)"
}
```

**Expected:** gateway and models each print `endpoint IP match`; optional Blob
adds a third line. Blob DNS alone does **not** prove Blob data access. For a
non-Windows executor the platform owner needs equivalent resolver tooling and
the same exact-IP evidence. Do not use hosts-file overrides.

7. Stay on **B**, in this same session. Run only the
   [trace-aware API-key calls](acceptance.md#trace-aware-calls-from-the-selected-existing-client)
   and the following [same-route negative-key checks](acceptance.md#5-reject-missing-and-invalid-runtime-keys).
   They use the allowlisted `$o` subset loaded above and retrieve the key using
   **B's own identity**, in memory. Do not grant roles or switch authentication
   automatically if this fails.
8. Use the [sanitized evidence return](acceptance.md#return-existing-client-evidence-to-the-deployment-host)
   to send results back to **A**. A continues roles/telemetry/drift verification.
9. After **each** access closure, repeat the export, transfer and client checks
   with a new run ID and current stage. The previous file is not final-stage
   proof. After Step 5, require `private-only`, then complete manual acceptance.

`Test-ModelAliases.ps1` still reads Terraform outputs itself; it has **no metadata
handoff argument**. Use it only as a separate smoke-test companion when the caller
already has approved backend access. It does not supply trace/negative/public-
boundary proof. Do not duplicate its billable calls in the procedure above.
An intentionally configured Entra caller needs its separately approved test;
do not silently change that design to API keys.

### Test with the optional sample VM

**Where:** the approved operator terminal; Run Command executes inside the VM.
Use this block only when you own its test/power cycle. A newly created VM may
already be running: if it belongs to this run, first perform
[Step 6](#step-6-stop-the-vm-when-you-are-done), then return here. Do not stop or
take over another operator's running VM.

```powershell
$vmId = terraform output -raw private_test_vm_id
if ($LASTEXITCODE -ne 0 -or -not $vmId -or
    -not $vmId.StartsWith("/subscriptions/$subscriptionId/", [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Missing test VM or wrong subscription. Do not start a different VM.'
}
$powerCodes = @(az vm get-instance-view --subscription $subscriptionId --ids $vmId `
    --query 'instanceView.statuses[].code' --output tsv --only-show-errors)
if ($LASTEXITCODE -ne 0 -or $powerCodes -notcontains 'PowerState/deallocated') {
    throw 'Confirm exclusive ownership and deallocated state before taking this test cycle.'
}
try {
    az vm start --subscription $subscriptionId --ids $vmId --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'VM start failed.' }
    .\scripts\Test-PrivateGateway.ps1
}
finally {
    az vm deallocate --subscription $subscriptionId --ids $vmId --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Cleanup failed. The owner must deallocate this VM.' }
    $powerCodes = @(az vm get-instance-view --subscription $subscriptionId --ids $vmId `
        --query 'instanceView.statuses[].code' --output tsv --only-show-errors)
    if ($LASTEXITCODE -ne 0 -or $powerCodes -notcontains 'PowerState/deallocated') {
        throw 'VM deallocation is not confirmed; contact the cleanup owner now.'
    }
}
```

**Expected:** the sanitized probe report contains `"passed": true`, `OK` for
every alias, and gateway/model addresses within their **respective** endpoint
subnet CIDRs. The key is retrieved through the VM identity, not printed or
passed as a command argument. The `finally` block deallocates the VM even on
probe failure; if the process/machine dies, the named cleanup owner must perform
Step 6 manually. A guest-agent/Run Command error needs platform egress/agent
investigation, not public SSH or broader VM roles.

**Stop if either client path fails.** Check approval, private DNS, permissions
and outbound integration. During initial staging, this is only an initial
check because model public access is still on. Repeat your selected client
procedure after each access closure.

## Step 4: Disable model public access

For the staged path with a still-public gateway, plan **without** the temporary
models-public override. If the gateway is already disabled, do not use this
intermediate profile; follow [existing private deployments](#existing-private-deployments).

```powershell
terraform plan -input=false "-var-file=$customerVarFile" @additionalInputArgs `
    "-var-file=$networkOwnershipFile" '-var-file=profiles\private-connectivity.tfvars.json' `
    @endpointCompatibilityArgs '-out=private-connectivity.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Model-private plan failed.' }
terraform show private-connectivity.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the model-private plan.' }
```

Expected change: model public access becomes `Disabled` (network ACL Deny). Gateway public access stays `Enabled`.

```powershell
terraform apply "private-connectivity.tfplan"
if ($LASTEXITCODE -ne 0) { throw 'Model-private apply failed; stop.' }
```

Repeat Step 3's readiness and **selected client** checks now. Do not close
gateway access unless those checks succeed with model public access disabled.

<a id="optional-final-stage-disable-gateway-public-access"></a>

### Required final stage: Disable gateway public access

After both private endpoints are approved/provisioned and the private probe
succeeds with model public access disabled, review all callers. A hosted agent, public CI
runner or laptop needs its own supported route and DNS to the gateway private
endpoint. Entra authentication does not supply that network route.

For an existing gateway that is still public, plan the explicit final profile:

```powershell
$networkProfile = 'private-only'
terraform plan -input=false "-var-file=$customerVarFile" @additionalInputArgs `
    "-var-file=$networkOwnershipFile" "-var-file=profiles\$networkProfile.tfvars.json" `
    @endpointCompatibilityArgs '-out=private-only.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Final private plan failed.' }
terraform show private-only.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the final private plan.' }
```

Retain all original environment and selected ownership inputs before the profile.
Expected networking change: gateway public access becomes `Disabled`; existing endpoints, outbound
integration, private models and gateway identity remain. Stop on unexpected
replacement, deletion or public reopening. After reviewing the plan:

```powershell
terraform apply "private-only.tfplan"
if ($LASTEXITCODE -ne 0) { throw 'Gateway-private apply failed; stop and inspect actual state.' }
```

Terraform already maps the setting to ARM `publicNetworkAccess`. However,
earlier Terraform/CLI updates failed; only the later portal operation is
confirmed successful. Allow asynchronous completion, then verify ARM
`Disabled` / `Succeeded` and the private connection `Approved` / `Succeeded`.
Do not mistake an initial accepted response for completion, invent a fixed
timeout, or automatically reopen public ingress after a failure. On timeout or
error, inspect the actual operation/resource state before any new plan/retry.
This staged procedure is not a verified one-apply private-only creation path.

**Already disabled through the portal?** Do not toggle it back. Select
`private-only`, preserve the authoritative backend/state and original inputs,
discard stale plans, and inspect a fresh full plan. If it exits `0`, no apply is
needed. Other changes require separate review, not an automatic apply.

## Step 5: Prove the final private path

Repeat Step 3's readiness checks and the procedure for your **selected** client
after the final closure. Do not run the VM wrapper on an environment without
the sample VM. Then check drift with the required final profile:

```powershell
$networkProfile = 'private-only'
terraform plan -input=false "-var-file=$customerVarFile" @additionalInputArgs `
    "-var-file=$networkOwnershipFile" "-var-file=profiles\$networkProfile.tfvars.json" `
    @endpointCompatibilityArgs -detailed-exitcode
switch ($LASTEXITCODE) {
    0 { 'No pending Terraform changes.' }
    1 { throw 'Drift plan failed; state is not verified.' }
    2 { throw 'Changes remain. Review a new saved plan; do not auto-apply.' }
    default { throw 'Unexpected Terraform exit code.' }
}
```

**Private-route check complete when:** the selected client's DNS and every
alias check pass (the VM report specifically requires `passed: true` and `OK`),
both gateway and model public access are disabled, and the
plan exits `0`. Also require an authenticated public request to be rejected by the network boundary.
A missing/invalid-key failure on the private route is not that proof. Record
required hosted-agent reachability and fresh telemetry separately.

The VM probe also rejects missing/invalid keys on the same route after positive
controls and emits per-call trace IDs. It does not itself verify all role
bindings, connections or telemetry ingestion.
Complete the [customer acceptance guide](acceptance.md) before handing over the
deployment, not the public-path plan/apply. A DNS/inference pass is only the
private-route part of acceptance. The VM-based [end-to-end runner](end-to-end.md) adds
VM lifecycle handling, backend checks, correlated telemetry and portal evidence.
Pass `-NetworkProfile private-only` to that runner for a disabled gateway; it
uses the same selected profile for both the live posture check and drift plan.
Also pass the complete customer and ownership files through `-AdditionalVarFile`;
do not lose existing-network inputs during acceptance. Its private runtime pass
does not certify public network rejection.

## Step 6: Stop the VM when you are done

Skip this step if no sample VM exists. Use it for your approved cleanup,
including recovery after a terminated terminal. Do not act on somebody else's
running session.

```powershell
$vmId = terraform output -raw private_test_vm_id
if ($LASTEXITCODE -ne 0 -or -not $vmId -or
    -not $vmId.StartsWith("/subscriptions/$subscriptionId/", [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Missing test VM or wrong subscription.'
}
az vm deallocate --subscription $subscriptionId --ids $vmId --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'VM deallocation failed; contact the cleanup owner.' }
$powerCodes = @(az vm get-instance-view --subscription $subscriptionId --ids $vmId `
    --query 'instanceView.statuses[].code' --output tsv --only-show-errors)
if ($LASTEXITCODE -ne 0 -or $powerCodes -notcontains 'PowerState/deallocated') {
    throw 'VM is not confirmed deallocated; cleanup is incomplete.'
}
'PowerState/deallocated confirmed.'
```

**Expected:** the confirmation line. `PowerState/stopped` is insufficient.
Use Step 3's owned power cycle for another smoke test, or leave it deallocated
for the automatic runner. Disks, endpoints, DNS, models and monitoring still
incur their continuing charges.

## Existing private deployments

Preserve the authoritative state/backend and all approved environment and
network-ownership inputs.
Complete or preserve the Private-only end state:

- Gateway already `Disabled`: set `$networkProfile = 'private-only'`, inspect
  a fresh plan with that profile and the retained compatibility arguments,
  then run Step 5. Do not repeat staging. If models still need closure, first
  perform Step 3's readiness/client checks and keep `private-only` for that plan;
  never select an intermediate profile that reopens the gateway.
- Gateway still `Enabled`: verify the existing private path, then follow the
  required gateway-disable stage above. This intermediate state is not
  Private-only acceptance.

For the already-disabled entry, a fresh full review plan is:

```powershell
terraform plan -input=false "-var-file=$customerVarFile" @additionalInputArgs `
    "-var-file=$networkOwnershipFile" '-var-file=profiles\private-only.tfvars.json' `
    @endpointCompatibilityArgs '-out=private-maintenance.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Private maintenance plan failed.' }
terraform show private-maintenance.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the private maintenance plan.' }
```

No changes means no apply is needed; continue to Step 5. If changes are required,
use the main guide's approval gate before `terraform apply private-maintenance.tfplan`,
check its exit code, and repeat readiness/runtime checks. Do not apply stale
plans or re-enable public access as an automatic recovery step.

The default `create` mode retains existing sample resource names and Terraform
addresses. Changing an already-deployed foundation to `existing` is **not** a
normal mode toggle or automatic migration: it would remove sample-owned
resources, and the created VNet has a `prevent_destroy` guard to block
accidental removal. Do not bypass this guard, copy state or import resources
into a second owner. Arrange a separately reviewed state/migration plan before
changing ownership.

Switching `private_dns_zone_group_management` between `workload` and `platform`
also needs a reviewed state handoff, not a routine flag flip. Review zone-group
removal/recreation, DNS continuity and the single authoritative owner before
changing the setting; no automatic import or ownership transfer is provided.

Changing private-endpoint subnet IDs replaces the affected endpoints, as do
service-target changes. Recheck approval, DNS and private calls after an approved
replacement. Moving existing gateway/agent integration or client subnets is a
separate migration; the sample does not automatically relocate a VM/NIC.
