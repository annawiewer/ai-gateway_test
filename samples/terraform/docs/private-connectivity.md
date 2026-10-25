# Private connectivity path

This is the private alternative to the [public endpoint path](../README.md#public-endpoint-path),
not an extra step after its public plan/apply. It applies to the existing legacy
gateway resource retained by this sample; see [resource type and lifecycle](reference.md#resource-type-and-lifecycle).

**Goal:** prove this route works privately:

```text
Private client -> gateway private endpoint -> private model endpoint
```

**Choose the intended end state:**

| Setting | `private-connectivity` (hybrid) | `private-only` (final gateway isolation) |
| --- | --- | --- |
| `enable_private_networking` | `true` | `true` |
| `gateway_private_endpoint_manual_approval` | `true` (Pending, then explicitly approve) | `true` |
| `gateway_public_network_access` | `Enabled` | `Disabled` after private-route verification |
| `models_public_network_access` | `Disabled` after step 4 | `Disabled` |

The profiles express desired configuration, not runtime proof. The public
Terraform defaults and the existing hybrid profile remain unchanged. Keep the
**selected** profile last on every plan, including drift/monitoring changes;
it overrides earlier var-files and `terraform.tfvars`. A wrong hybrid selection
can plan to reopen a disabled gateway.

The gateway endpoint uses a manual request followed by an explicit APIM
connection approval. Terraform waits for approval before creating its DNS zone
group. Approval first verifies that the service-created connection belongs to
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

> **October 25, 2026: portal disable succeeded for the observed gateway.**
> ARM confirmed `Disabled` / `Succeeded` with an approved private connection.
> A later private-agent request returned OK with correlated gateway/backend
> HTTP 200; an authenticated public gateway request returned network-denial 403.
> This does not prove the Terraform update path or first-create behavior.
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

Complete the [main prerequisites](../README.md#before-you-start) and
[shared setup](../README.md#shared-setup), retaining the existing input file and
state/backend. Do not run the public-path plan/apply. Additional requirements:

- Complete the [two-stage OTLP destination setup](monitoring.md) before planning
  the exporter. Keep the private profile on those plans too; readiness discovery
  must not re-enable a private gateway/model backend or rebuild the gateway.
- `Microsoft.Network` registered
- For the test VM: `Microsoft.Compute`, regional VM quota, and permission to use VM Run Command

### Test-client permissions

The Terraform deployment identity and the VM's managed identity have different
jobs. Creating role assignments alone does **not** authorize creating a custom
role definition.

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

## Step 1: Choose your test client

Your laptop is not on the VNet. The easiest option is the optional test VM (no VPN, no inbound SSH). Add these to `terraform.tfvars`:

```hcl
enable_private_test_client         = true
private_test_client_ssh_public_key = "ssh-ed25519 <your-public-key>"
```

- Use a **public** key only. Never paste a private key or password.
- The VM is billable, has no public IP and denies inbound traffic. The probe uses Run Command, not SSH.
- Already have a client on the VNet? Skip the VM and run equivalent DNS and inference checks from it. `Test-PrivateGateway.ps1` requires the VM.

## Step 2: Create networking with models temporarily public

Use this stage when adding private networking to an existing legacy gateway
whose model backend is still public. It is not the final posture, and it is not
a way to create a new legacy gateway. **Do not run it on an already-disabled
gateway or backend.**

```powershell
$networkProfile = 'private-connectivity'
terraform plan "-var-file=profiles\private-connectivity.tfvars.json" "-var=models_public_network_access=Enabled" "-out=private-connectivity-stage1.tfplan"
```

Review the plan: gateway and model public access are both enabled, and networking
plus the VM (if enabled) are created. Do not apply unexpected replacements.

```powershell
terraform apply "private-connectivity-stage1.tfplan"
```

## Step 3: Check the private route

```powershell
.\scripts\Test-PrivateGateway.ps1
```

The wrapper runs the probe inside the VM, which must already be running. It checks
that the gateway and model hostnames resolve to the private endpoint subnet and
that every alias answers `OK`. The VM gets the gateway key through managed
identity. No key is printed or passed as an argument.

**Model prerequisite:** all aliases must support the probe's OpenAI Chat
Completions request, including `max_tokens` and `temperature`. The sample's
`gpt-4.1` and `gpt-4.1-mini` configuration is the reference. Responses-only,
embeddings, image, or other API formats need their own test. The probe rejects
incompatible API metadata before DNS/key retrieval; it does not interpret that
rejection as a networking failure. See [probe compatibility](reference.md#probe-compatibility).

**Stop if this fails.** Check endpoint approval, private DNS, permissions and outbound integration. A pass here is only an initial check, because model public access is still on.

## Step 4: Disable model public access

Plan **without** the temporary override:

```powershell
terraform plan "-var-file=profiles\private-connectivity.tfvars.json" "-out=private-connectivity.tfplan"
```

Expected change: model public access becomes `Disabled` (network ACL Deny). Gateway public access stays `Enabled`.

```powershell
terraform apply "private-connectivity.tfplan"
```

### Optional final stage: Disable gateway public access

Skip this stage if public gateway ingress is intentional. Otherwise, after both
private endpoints are approved/provisioned and the private probe succeeds with
model public access disabled, review all callers. A hosted agent, public CI
runner or laptop needs its own supported route and DNS to the gateway private
endpoint. Entra authentication does not supply that network route.

For an existing gateway that is still public, plan the explicit final profile:

```powershell
$networkProfile = 'private-only'
terraform plan "-var-file=profiles\$networkProfile.tfvars.json" "-out=private-only.tfplan"
```

Retain all original environment inputs before the profile. Expected networking
change: gateway public access becomes `Disabled`; existing endpoints, outbound
integration, private models and gateway identity remain. Stop on unexpected
replacement, deletion or public reopening. After reviewing the plan:

```powershell
terraform apply "private-only.tfplan"
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

Set `$networkProfile` to the chosen end state (`private-only` or
`private-connectivity`) before running these commands:

```powershell
.\scripts\Test-PrivateGateway.ps1
terraform plan "-var-file=profiles\$networkProfile.tfvars.json" -detailed-exitcode
```

**Private-route check complete when:** the probe reports `"passed": true` with
`OK` for every alias, and the plan exits `0`. For private-only acceptance, also
require an authenticated public request to be rejected by the network boundary.
A missing/invalid-key failure on the private route is not that proof. Record
required hosted-agent reachability and fresh telemetry separately.

The probe also rejects missing/invalid keys on the same route after positive
controls and emits per-call trace IDs. It does not itself verify all role
bindings, connections or telemetry ingestion.
Complete the [customer acceptance guide](acceptance.md) before handing over the
deployment, not the public-path plan/apply. A DNS/inference pass is only the
private-route part of acceptance. The [end-to-end runner](end-to-end.md) adds
VM lifecycle handling, backend checks, correlated telemetry and portal evidence.
Pass `-NetworkProfile private-only` to that runner for a disabled gateway; it
uses the same selected profile for both the live posture check and drift plan.
Its private runtime pass does not certify public network rejection.

## Step 6: Stop the VM when you are done

```powershell
$vmId = terraform output -raw private_test_vm_id
$subscriptionId = ($vmId -split '/')[2]
az vm deallocate --subscription $subscriptionId --ids $vmId
```

Restart with `az vm start` using the same arguments. Disks, private endpoints, DNS, model deployments and monitoring still incur charges.

## Existing private deployments

Preserve the authoritative state/backend and all approved environment inputs.
Choose the intended ingress explicitly:

- Gateway already `Disabled`: set `$networkProfile = 'private-only'`, inspect
  a fresh plan with that profile last, then run Step 5. Do not repeat staging.
- Gateway intentionally `Enabled`, model already `Disabled`: set
  `$networkProfile = 'private-connectivity'`, inspect a fresh plan and run Step 5.
- Gateway still `Enabled`, but private-only required: verify the existing
  private path, then follow the optional final stage above.

Do not apply stale private-only plans, and do not re-enable public access as an automatic recovery step.
