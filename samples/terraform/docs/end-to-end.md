# Optional sample-VM acceptance runner

<a id="end-to-end-verification-and-portal-acceptance"></a>
<a id="customer-like-rehearsal-and-portal-acceptance"></a>

This is the **optional sample-managed VM** runner, not a requirement for every
private client. For an existing private client without that VM, use the
[private-client handoff](private-connectivity.md#test-from-an-existing-private-client)
and [manual acceptance](acceptance.md) instead.

The offline suite, live backend verifier and authenticated portal review are
separate gates. **None is a substitute for the other two.** The verifier never
deploys, repairs, grants roles, switches SKUs or deletes Azure resources.
It does read ARM, run a full Terraform drift plan and write local reports.
The explicit runtime flag additionally starts the VM, uses Run Command, calls
billable inference and deallocates the VM. The portal review remains manual.

**Choose the right route before running anything:**

| Your situation | Use |
| --- | --- |
| No sample test VM; an existing private client is available | The [private-client checks](private-connectivity.md#test-from-an-existing-private-client) and [manual acceptance](acceptance.md), including its [manual portal record](acceptance.md#8-record-the-manual-portal-review). This runner has no existing-client runtime mode. |
| Sample VM is configured; you want Azure-read-only diagnostics and a full drift plan | Step 2 also writes local reports. Expect incomplete acceptance: no model calls/telemetry proof are performed. |
| Sample VM is configured and initially deallocated; costs are approved | Step 2's complete parameter selection, then Step 3's explicit runtime command. |
| Deployment needs a post-profile compatibility override | Manual acceptance, retaining that override. This runner supports extra var-files before the access profile, not extra `-var` arguments afterward. |

Even diagnostics require the sample's **VM ID** and
`private_probe_configuration` output. Without that configured VM, those checks
cannot pass; do not enable new infrastructure merely to obtain a green report.

## Scope and environment gate

Keep the legacy `AIGateway` SKU and private-endpoint architecture. All application
resources belong in one group; the VM's custom role definition is subscription
scoped, with its assignable scope limited to that group. Retained migration groups
must be cleaned up through a separately reviewed operation before final acceptance.
The only additional placement exception is the exact gateway publisher assignment
on the Insights-linked DCR in a verified Azure-managed monitoring group; see
[OTLP ownership and setup](monitoring.md). No blanket `MA_*` exemption exists.
During a three-group migration, first use the manual private/runtime checks in
[acceptance.md](acceptance.md) to establish backend health before approving old-group
cleanup. The strict final runner deliberately does not waive its placement gate.

| Rehearsal | What it proves | Prerequisite |
| --- | --- | --- |
| Clean checkout, offline | Reproducible configuration and regression checks | No Azure credentials, state or deployment input files |
| Existing legacy integration | Configuration and runtime of an existing gateway | Exclusive ownership of its authoritative state, approved inputs and scope |
| New gateway deployment | Resource creation from the selected inputs | Confirm the exact resource type/SKU is available in the approved subscription/region, plus quota, policy and deployment permissions |

A check of an existing gateway does not prove that a new gateway can be created.
A container sandbox can isolate tools but cannot emulate Azure provisioning,
quotas, Private Link, DNS, managed
identities, ingestion or the real portal. No hosted agent/image is deployed by
this sample, so image pull, artifact access and agent execution need a separate
approved test. Private routing alone is **not** private-only gateway ingress.
The explicit `private-only` profile requests disabled gateway public access.
The [scoped verification record](reference.md#private-only-gateway-ingress-status)
separates the October 27 original-SKU creation/private-closure rehearsal from
the October 25 portal/private-agent proof. Neither verifies your environment
or establishes private-from-first-create.

If the optional **private hosted-agent extension** is selected, enable its
[private configuration from account creation](private-hosted-agent.md#configure-new-agent-accounts-from-the-start).
Application deployment, runtime identity binding and
[hosted-agent repeat checks](private-hosted-agent.md#repeat-the-evidence-not-the-original-provisioning)
are separate from this runner. The base `project_id` output still names the
base project; use `private_hosted_agent` outputs for the private reference.

Before any new cloud rehearsal, record the approved subscription/tenant, regions,
unique environment name/group, model quota, permissions, cost ceiling, expiry,
cleanup owner and protected state location. Use a separate identity/state and
prefer a separate test subscription. A budget alert is not a hard spending cap.
Do not proceed without this approval and SKU eligibility. There is deliberately
no credentialed cloud deployment workflow yet.

For an existing deployment, preserve its backend/state, exact stable naming inputs
and any migration revision. Never copy its state into a second active environment.
For a genuinely new, eligible environment use the
[base example for the selected scenario](../01-04-deployment.md#2-create-or-select-a-base-input-file)
with its complete create/existing ownership inputs and approved private stage,
not another developer's local migration overrides.
Follow the [private guide](private-connectivity.md) for preflight and staged,
reviewed plan/apply. Inspect exact target IDs, public access, role scopes and every
destroy/replace action; retain gateway `prevent_destroy`. The acceptance runner is
**post-deployment**, not an automatic deployment controller.

## 1. Clean checkout and offline CI

Record the approved immutable source SHA and its CI result. If rerunning
maintenance fixtures is required, follow [Offline checks](reference.md#offline-checks)
in a separate clean checkout without deployment inputs/state, not the configured
workload directory. The helper can download providers and writes local files;
"offline" means no Azure operations, not network-free or read-only. An existing
approved CI result can be retained rather than rerunning those fixtures.

## 2. Read-only backend checks

**Read-only describes Azure effects, not local effects:** this step includes a
full Terraform plan and local report writes, and still requires the sample VM.

Reconnect the approved state/backend and supply its existing private inputs.
Ensure the checkout is clean, Terraform is initialized and Azure CLI is signed
into the approved context. These checks need resource/role read access; telemetry
also needs Log Analytics and AMW Prometheus query access.

**Where:** the configured workload's `samples\terraform` directory, not the
separate clean checkout used for generic fixtures. Complete or restore the
main guide's [Azure context](../01-04-deployment.md#inputs-and-state) and
[full input selection](../01-04-deployment.md#compose-the-inputs) first. Do not copy
state between these directories.

```powershell
foreach ($name in @('subscriptionId', 'tenantId', 'workloadVarFile',
                    'additionalVarFiles', 'networkOwnershipFile', 'endpointCompatibilityArgs')) {
    if (-not (Get-Variable -Name $name -ErrorAction SilentlyContinue)) {
        throw "Missing $name. Restore the main guide's approved context and input files."
    }
}
if ($endpointCompatibilityArgs.Count -ne 0) {
    throw 'This deployment needs a post-profile override; use the manual acceptance path.'
}
$resourceGroup = terraform output -raw resource_group_name
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the authoritative workload group.' }
$parameters = @{
    SubscriptionId = $subscriptionId
    TenantId = $tenantId
    ResourceGroup = $resourceGroup
    ReportDirectory = 'C:\protected-evidence\gateway'
    AdditionalVarFile = @($workloadVarFile) + $additionalVarFiles + @($networkOwnershipFile)
    NetworkProfile = 'private-only'
}
.\scripts\Test-DeploymentAcceptance.ps1 @parameters
```

Replace `ReportDirectory` with the approved restricted evidence folder before
running. `AdditionalVarFile` is the full ordered list, **including** the
network-ownership file; omitting it can lose `existing` mode. It is not enough
that an input file with a nonautomatic name happens to be present in the directory.

Reports go into a unique run-ID subdirectory. Store them outside the checkout or
in the ignored `acceptance-results` directory with access restricted to the test
team; IDs, IPs and screenshots still contain operational information. Do not
publish them to a public repository or an unrestricted CI artifact.

Always pass `private-only` for final private acceptance. The backwards-compatible
runner default, `private-connectivity`, checks an intermediate provisioning state;
it is not a third deployment path or final Private-only acceptance.
The live check requires the exact gateway access value in the selected file;
it does not accept either value indiscriminately. The report records the
selected profile, expected and observed access, and the untested public-rejection
boundary. A mismatch fails and blocks the runtime probe.

The default checks context, a clean source commit, single-group state placement,
live identities/resources/catalog/aliases, six exact service roles, three
connections, OTLP destination/exporter and one exact DCR publishing role, endpoint provisioning **and** approval, DNS
links and a full drift plan. It does not start the VM, retrieve keys or call
models. Therefore runtime/telemetry remain NOT RUN/BLOCKED and it exits with an
incomplete-acceptance error, even if all read-only checks pass.

The legacy preview's catalog GET can omit `apiFormat`. The runner records this
verification boundary: it requires compatible output metadata and live supported
endpoints/alias targets; when `apiFormat` is returned it must match.

The exporter must return `kind = OpenTelemetry` (case-insensitive), the expected
Insights ID, all three actual OTLP endpoints, system-identity audience
`https://monitor.azure.com` and `payloadCapture = false`, without connection
strings or custom credential headers. Missing kind, incomplete endpoints or a
legacy Application Insights exporter fail. The runner verifies the linked
DCR/DCE/AMW, expected Log Analytics destination and managed-group ownership.
Do not create a second monitoring stack in the portal or assume ingestion delay
repairs missing configuration. Actual API behavior, delivery and visible portal
metrics still need runtime proof.

Every drift plan includes `01-04-profiles\<NetworkProfile>.tfvars.json` last.
For more approved nonautomatic inputs, add them to `$additionalVarFiles` in
the main guide and rebuild `$parameters`; do not replace the complete list with
just one runtime file. Existing automatic
tfvars still apply: review them and `TF_VAR_*` values. Remove hidden
`TF_CLI_ARGS`/`TF_CLI_ARGS_plan`; targeted plans are not acceptance. State, raw
plan text and raw service errors are never included in reports.
An earlier `Disabled` value does not override the intermediate profile's `Enabled`.
Select the correct `-NetworkProfile` instead. Drift exit `2` requires review;
the runner never applies that plan or changes gateway public access.

## 3. Explicit private runtime and telemetry

Only after approving model and VM costs:

The VM must be **deallocated**, not running or merely stopped. If the preceding
smoke test used it, follow [confirmed deallocation](private-connectivity.md#step-6-stop-the-vm-when-you-are-done)
first. Do not start it manually before this command; the runner owns that cycle.

On Windows, the runner quotes HTTP URL arguments for the `az.cmd` launcher so
`cmd.exe` does not split Prometheus query parameters at `&`. Direct executable
and non-Windows Azure CLI invocations retain their normal argument handling.

```powershell
.\scripts\Test-DeploymentAcceptance.ps1 @parameters -RunPrivateProbe -TelemetryWaitSeconds 300
```

This flag permits starting the **output-identified test VM**, running its probe
and deallocating it. It requires the VM to be initially deallocated so it will
not take over someone else's running session. All prerequisite checks must pass
before it starts. It verifies deallocation in `finally`, including probe failure.
If the process/machine is killed, `finally` cannot guarantee cleanup: the named
cleanup owner must check power state and deallocate the exact VM manually.
No cleanup failure is a pass.

The probe checks each DNS name against its service's expected private endpoint
subnet CIDRs, makes one positive chat call per alias (8 requested output tokens,
90-second HTTP timeout) and then two same-route negative-key calls. Positives must
return HTTP 200 and exactly `OK`. Negative requests must fail with 401 or a key/authentication-specific
403; a generic firewall 403, 429, 500 or timeout is not authentication proof.
There is no load test or model-call retry. Existing managed-identity key lookup
retries at most 12 times, with 15-second waits for 403 propagation.

Neither a private probe nor ARM `Disabled` alone proves public network
rejection. This runner does not send a valid-credential request from outside
the private network; `privateOnlyIngress` remains `NOT certified`, even on a
backend pass. A separate approved public-boundary test and any required
hosted-agent test are needed for private-only end-to-end acceptance.
Use the [public-boundary mini-steps](acceptance.md#prove-public-network-denial-with-a-valid-gateway-key)
for the separate host, identity, metadata and sanitized evidence. Do not use
missing/invalid-key responses as a substitute.

Each positive request sends a unique W3C `traceparent`. The verifier queries the
linked Log Analytics workspace for those exact `TraceId` values in `OTelSpans`
and `OTelLogs`: successful gateway server spans for every call and at least one
correlated log. It also requires positive, fresh
`azure.ai_gateway.client.token.usage` samples through AMW Prometheus, scoped to
the same Insights resource, gateway workspace and UTC window. These samples are
not an exact per-run token total, especially under concurrent traffic. Missing
logs mean delivery is unproven; investigate emission rather than assuming every
successful request must log. Polling is bounded by the configured ingestion wait
(0-900 seconds, excluding individual CLI call duration).
It does **not** substitute historical traffic or exporter existence for delivery.
If this preview does not propagate W3C IDs into that schema, the check fails:
investigate actual exporter correlation support before changing the assertion.
Trace propagation and the telemetry schema still require real-environment proof.
For manual execution, the [trace/log query](acceptance.md#inspect-the-traced-requests-and-correlated-logs)
shows the success fields, and the [parameterized token-metric query](acceptance.md#query-the-token-metrics-for-the-same-destination-and-window)
uses the verified destination and actual request UTC window.

`acceptance.json` reports each check and non-secret evidence. CLI/HTTP operations
can also have platform-level waits; this runner is not a hard wall-clock or cost
limiter. Use a supervised run and a separate cost/VM watchdog for unattended use.

### Read the result before proceeding

Open the **new run's** `acceptance.json` in VS Code. Locate `backendStatus` and
the failed/blocked checks; use that run's paths for the later portal step.
Never edit a backend status to make the report pass.

| Result | Meaning | Next action |
| --- | --- | --- |
| Read-only checks pass, runtime/telemetry `NOT RUN` or `BLOCKED` | Expected without `-RunPrivateProbe`; acceptance is incomplete | Decide whether the explicit billable VM run is approved, or retain diagnostics only |
| A prerequisite `FAIL`, including missing VM configuration | The exact required check failed or this runner is the wrong route | Read that check; use the relevant owner or manual-client path, not an automatic deployment/repair |
| Runtime/telemetry `FAIL` or `BLOCKED` | Private calls, authentication or fresh telemetry were not proved | Investigate the named gate; do not proceed to final portal sign-off |
| `backendStatus` is `PASS` | This runner's backend checks passed for this run | Perform Step 4's independent UI review; public-network rejection and agent runtime still need separate evidence |
| VM cleanup failure | Compute may still be allocated even if inference worked | Have the cleanup owner deallocate the exact output-identified VM and verify power state immediately |

## 4. AI Gateway portal review

Require `backendStatus = PASS` for the current VM run, then perform all six
checks in the canonical [AI Gateway portal checklist](acceptance.md#ai-gateway-portal-checklist).
It includes route identification, bounded calls, numeric metrics comparison
and redaction requirements. Return here only to validate the VM manifest.

Without a sample VM, use [manual portal evidence](acceptance.md#record-the-manual-portal-evidence)
after the manual backend checks instead. Do not create a VM report or enable
infrastructure to use the shared checklist.

### Validate the sample-VM portal manifest

**VM-runner route only.** The runner creates `portal-evidence.json`; require
`backendStatus = PASS` in its actual current `acceptance.json` before using this
validator. For manual acceptance, return to the
[manual evidence procedure](acceptance.md#8-record-the-manual-portal-review)
instead; do not manufacture either generated report.

**File steps:** open the generated `portal-evidence.json` beside this run's
backend report, fill each item from actual observations, save the redacted
evidence files beside it, and press **Ctrl+S**. Replace `<run-id>` below with
that exact directory name. Do not reuse a manifest from an older deployment.

For each checklist item fill `status`, `observed` and a relative `evidence`
filename for a redacted screenshot or observation text beside the manifest.
Fill `reviewer` and `reviewedUtc` only after the review. For `metrics`, record
the underlying `source` query/metric definition, UTC window (at most 24 hours and
covering the probe), numeric `portalValue` and `referenceValue`, and an
`explanation` of identical filters/aggregation. Nonsecret trace IDs connect the
reference telemetry to this run. Follow the shared checklist's redaction rules;
the validator does not independently inspect the browser.

```powershell
.\scripts\Complete-PortalAcceptance.ps1 `
    -BackendReport 'C:\protected-evidence\gateway\<run-id>\acceptance.json' `
    -PortalEvidence 'C:\protected-evidence\gateway\<run-id>\portal-evidence.json'
```

This validates context, completeness, evidence files and the metrics comparison
and writes a separate `acceptance-with-portal.json`. It **does not automate the
browser or independently verify the observations**: UI acceptance is explicitly
operator-attested. Failed backend checks cannot be overridden, and the original
backend report is preserved. No complete end-to-end PASS is emitted without both.

<a id="5-repeatability-handover-and-cleanup"></a>

## 5. Repeatability, evidence and cleanup

Rerun the same approved commit/inputs against the same exclusively owned state.
Require another zero-drift result and new runtime/telemetry/UI evidence; do not
reuse an old portal pass. Testing creation of a new gateway remains a separate gate.
Keep failed reports and non-secret correlation IDs for support; never repeatedly
recreate a failing gateway endpoint without a diagnosed fix.

Keep the approved commit, input/state ownership instructions, source CI result,
deployment evidence, acceptance reports, known limitations and cleanup owner
in your protected operational record. For the VM-runner route, retain both the
original backend report and the portal-completed report.
For teardown follow [protected cleanup](reference.md#cost-and-cleanup);
the runner does not disable gateway protection or automatically delete a group.
