# Update an existing gateway

[All scenarios](../../README.md#choose-your-scenario)

Use this entry whenever **the gateway workload is already deployed**, whether
public or private and whether its network is sample-managed or platform-owned.
This is not a new-deployment or example-file bootstrap path.

## Before you start

Identify the approved source revision, runner identity, backend/workspace/state
and complete input set that manage the workload. If those are unknown, stop
and obtain the owner handoff. Do not create a second state or import the same
resources into a second owner.

## Files for this scenario

| Files or configuration | Action |
| --- | --- |
| Existing workload input files | Retain them and make only the approved change. Do not replace them with `terraform.tfvars.example` or new lab defaults. |
| Existing network-ownership selection | Keep the current `create` or `existing` mode and complete network object, including extension fields and DNS-association ownership. |
| Existing access profile and additional inputs | Retain the approved end state, overrides and endpoint-compatibility exceptions. A private-only deployment stays private-only during monitoring and drift checks too. |
| Shared root `*.tf`, backend and authoritative state | Use the approved configuration and state. Selecting another scenario folder is not an upgrade mechanism. |

The [input composition rules](../../deployment.md#compose-the-inputs) still
apply on **every** plan, including helper-generated plans. Later variable
assignments replace whole objects. Keep complete approved objects rather than
overlaying only newly added nested fields.

Moving intact resource blocks between `.tf` files **within the same root** does
not by itself change resource addresses. Moving them into modules, changing
labels/keys or changing ownership does; those are separate migration decisions.

## Continue with the applicable update procedure

Start with the [shared update preflight](../../deployment.md#update-an-existing-gateway),
then use the procedure for the deployment's current access state below.

For an existing private deployment, follow
[Existing private deployments](../private-connectivity.md#existing-private-deployments).
Do not repeat the initial public stages or load `private-connectivity` over an
already private-only gateway.

For an existing public deployment, use its approved update runner and the
[shared plan-review controls](../../deployment.md#review-every-plan-before-apply).
Do not rerun the new-workload copy/bootstrap steps. A change to private access
is a separately planned transition, not an implicit effect of this entry.

Use the canonical [monitoring procedure](../monitoring.md) only for the relevant
monitoring task, with the same approved input set. Repeat the applicable
[acceptance checks](../acceptance.md) after the change; metadata discovery is
not runtime verification. The [sample-VM runner](../end-to-end.md) applies only
to that client and must explicitly select the current access profile.

## Stop conditions

Stop for an unknown state/owner, unexpected public reopening, changed gateway
private-endpoint approval mode, resource replacement/deletion or a network/DNS
ownership change that has not been separately approved.

Both private-access profiles set manual gateway private-endpoint approval;
changing that mode on an existing endpoint can force replacement. Preserve
the approved compatibility exception where applicable.

Do not bypass `prevent_destroy`, switch sample-owned networking to `existing`,
transfer zone-group ownership, change resource groups, or migrate the gateway
resource type/SKU as cosmetic cleanup. Those changes require their own reviewed
migration and acceptance plan.
