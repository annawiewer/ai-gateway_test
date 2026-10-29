# Scenario 03: new public lab

[All scenarios](../../README.md#choose-your-scenario)

Use this entry only for **a new workload whose public gateway and model
endpoints are explicitly approved**. This is an intentional public test setup,
not a prerequisite for either private scenario and not a troubleshooting fallback.

An existing private gateway belongs to [Scenario 04: the update entry](04-update-existing.md),
not this path.

## Before you start

- Agree the workload backend/state, target regions, model quota and permissions.
- Confirm that public access is allowed for the relevant resources. Authentication
  is still required; a public endpoint is not anonymous access.
- Review the [full sample scope](../../README.md#what-gets-deployed) and costs:
  the base agent account/project, Storage and Premium Registry remain, even for
  a simple model-call test.

## Files for this scenario

Paths are relative to `samples/terraform`.

| File | Action |
| --- | --- |
| [Base template (`01-04-terraform.tfvars.example`)](../../01-04-terraform.tfvars.example) | If no approved new-workload input file exists, copy to a protected file such as `terraform.tfvars`. Fill in subscription, regions, publisher contact, models and approved options. |
| [01-04-profiles/network-create.tfvars.json](../../01-04-profiles/network-create.tfvars.json) | Select as in the documented public procedure. This sets ownership mode only; with private networking disabled, it does not create the private foundation. |
| Private-access and existing-network profiles | Do not select them for this deliberately public scenario. Also check the complete input set for conflicting private settings; `network-create` does not reset other inputs. |
| All root `*.tf` files | Keep them together and normally unchanged. Do not delete private-network files or copy only the files that appear relevant. |

Keep `enable_private_networking = false` and the approved public access settings
in the effective input set. Follow the
[input composition rules](../../01-04-deployment.md#compose-the-inputs), not folder
order. No existing-network subnet or central DNS-zone IDs are needed for this
scenario. Environment values and state do not belong in public Git.

## Continue with the shared procedure

Follow the [shared runbook order](../../01-04-deployment.md#runbook-order), selecting
the [Public procedure](../../01-04-deployment.md#public). It covers saved-plan review,
separately approved apply, monitoring and model-alias checks.

Complete the applicable [acceptance requirements](../acceptance.md).
Model probes perform billable inference and must match the model's API support;
a successful public call is neither private-route proof nor full acceptance.
The sample-VM private-path runner is not the public-lab procedure.

**Stop** if public access lacks explicit approval, the workload is already
deployed with private access, the input set enables private resources
unexpectedly, or a plan proposes unapproved deletion/replacement. Do not
reopen restricted services or bypass policy to obtain a successful deployment.
