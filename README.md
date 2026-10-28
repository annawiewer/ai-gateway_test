# AI Gateway and Foundry with Terraform

Terraform reference for an Azure AI Gateway, Foundry models and supporting
infrastructure. Private deployments can reuse platform-managed networking and
central Private DNS without transferring ownership of those resources.

## Start here

> [!IMPORTANT]
> **[Open the step-by-step deployment guide](samples/terraform/deployment.md#start-here).**
> It covers prerequisites, configuration, approvals, deployment and verification.
> The [Terraform README](samples/terraform/README.md) explains the architecture
> and options; it is not a second deployment procedure.

**Existing network and central DNS?** Start with
[existing-network integration at a glance](samples/terraform/deployment.md#existing-network-integration-at-a-glance),
then continue through the same guide. Select `existing` network ownership and
retain the platform's network/DNS process and state.

The working directory remains **`samples\terraform`**. Follow the guide's
approved-source and input-file steps; do not move an existing workload's backend,
state or environment configuration to match a repository layout.

## Repository guide

| Location | Purpose |
| --- | --- |
| [`samples/terraform`](samples/terraform) | Terraform resource definitions, variable schema, outputs, provider lock file and input template. |
| [`profiles`](samples/terraform/profiles) | Network-ownership and access examples, selected and combined by the deployment guide. |
| [`examples`](samples/terraform/examples) | Optional adapter for an existing Terragrunt network/DNS workflow. |
| [`scripts`](samples/terraform/scripts) | Deployment verification, model probes and monitoring checks used by the guides. |
| [`docs`](samples/terraform/docs) | Architecture, request flow, private connectivity, acceptance and operating references. |
| [`tests`](samples/terraform/tests) and [offline CI](.github/workflows/terraform-offline.yml) | Repeatable maintenance checks. Keep these with the source; they do not create Azure resources. |

Start with the deployment guide rather than reading every folder. It identifies
which inputs to edit, which scripts to run and which optional sections apply.
Terraform, PowerShell and Azure CLI prerequisites are listed there.

## Scope and limitations

The sample supports **Public** and **Private-only** configurations and optional
private hosted-agent infrastructure. Terraform prepares agent infrastructure;
deploying agent application code is a separate activity. The original
`Microsoft.ApiManagement/service` resource and `AIGateway` SKU are retained.

**Preview reference, not a production guarantee.** Read the
[resource lifecycle](samples/terraform/docs/reference.md#resource-type-and-lifecycle)
and [limitations](samples/terraform/docs/reference.md#limitations) before deployment.
Private-only is a target reached through approved staged setup, not a guarantee
of private access from the first create operation. Resources and model calls
can incur charges.

See [LICENSE](LICENSE), [support](SUPPORT.md) and
[security reporting](SECURITY.md) for project information.

## Contributing

This project welcomes contributions and suggestions. Most contributions require you
to agree to a Contributor License Agreement (CLA) declaring that you have the right
to, and actually do, grant us the rights to use your contribution. For details,
visit [Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you
need to provide a CLA and decorate the PR appropriately (e.g., status check,
comment). Simply follow the instructions provided by the bot. You will only need to
do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/)
or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any
additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services.
Authorized use of Microsoft trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not
cause confusion or imply Microsoft sponsorship. Any use of third-party trademarks or
logos are subject to those third-party's policies.
