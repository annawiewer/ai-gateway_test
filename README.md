# AI Gateway tier in Azure API Management

[AI Gateway tier in Azure API Management](https://aka.ms/aigateway/docs) is the AI-focused tier of Azure API
Management. It puts model APIs and MCP tools behind one governed endpoint, with
access policies, networking and observability.

This repository contains **Terraform deployment guidance**, a complete
**Bicep/Python agent sample**, an **Azure CLI extension** and a **coding-agent
plugin**. These are separate entry points, not successive installation steps.

## Pick your task

| Task | Start here |
| --- | --- |
| Deploy or update gateway infrastructure with Terraform | [Choose one of four scenarios](samples/terraform/README.md#choose-your-scenario) |
| Try the separate Bicep/Python end-to-end sample | [Bicep sample and upstream snapshot](samples/bicep/README.md#snapshot-in-this-test-repository) |
| Understand the Terraform sample without running anything | [Beginner explanation](samples/terraform/docs/understand-the-sample.md) |
| Manage gateways, models, tools and policies with the CLI | [Azure CLI](#azure-cli) |
| Build an application that uses an existing gateway | [Coding-agent plugin](#coding-agent-plugin) |

**Already have platform networking and central DNS?** Start with
[Scenario 01: a new gateway on existing networking](samples/terraform/docs/scenarios/01-existing-network.md).
Its [filled walkthrough](samples/terraform/examples/filled/01-existing-network/README.md)
links the active base example, complete network inputs and shared procedure.
An existing *gateway* instead follows the
[Scenario 04 update guide](samples/terraform/docs/scenarios/04-update-existing.md).
All four scenarios use one shared Terraform implementation.

The [Bicep example](samples/bicep/README.md) is a separate deployment alternative,
not an extra Terraform step. It uses the newer `aigateways/Consumption` contract
and includes explicitly identified, unmerged upstream changes. It does not
update the Terraform sample or its customer-specific inputs. Do not use both
deployment tools to manage the same Azure resources.

> [!IMPORTANT]
> **Preview does not mean a free sample deployment.** Model calls, Premium
> Container Registry, Storage and monitoring incur costs. The Terraform sample
> retains a time-limited legacy SKU; read its
> [scope and preview limitations](samples/terraform/README.md#what-gets-deployed)
> before deploying.

## Azure CLI

Create and manage gateways, model registrations, MCP servers, and policies with
`az aigateway`. See the **[CLI installation and quickstart](cli/README.md)** for
one-line Bash and PowerShell installers, or browse the
[command reference](cli/command-reference.md).

## Coding-agent plugin

Use the plugin to **build an application on an existing gateway**. It discovers
registered models and MCP tool servers, then helps integrate model calls, tools
or a runnable agent into your application.

> **Consumption only.** The plugin is read-only against the gateway — it never
> provisions, updates, or deletes resources. Provisioning belongs to your
> approved infrastructure or gateway-administration process, not this plugin.

### What's inside

The `/ai-gateway:use-ai-gateway` skill guides discovery, selection, credential
retrieval and integration. Use `/ai-gateway:discover` to explore first or
`/ai-gateway:build` for the complete application workflow.

### Install

For **Claude Code / GitHub Copilot CLI**, install the upstream plugin through
the marketplace protocol:

```text
/plugin marketplace add Azure/ai-gateway
/plugin install ai-gateway@azure
```

<details>
<summary>Install in Cursor or Gemini CLI</summary>

**Cursor** — add the upstream repository as a team marketplace from **Dashboard → Plugins →
Add Marketplace → Import from Repo** (`https://github.com/Azure/ai-gateway`), then
install **ai-gateway** from **Customize**.

**Gemini CLI**:

```text
gemini extensions install https://github.com/Azure/ai-gateway
```

</details>

### Usage

Point the plugin at your gateway's **ARM resource id** (required to list its models and
tools) and describe what you want to build:

```text
/ai-gateway:build /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ApiManagement/service/<gateway> a service that summarizes support tickets
```

Replace the example resource ID with your gateway's full ID. For discovery only,
use `/ai-gateway:discover` with that same ID.

### Security

The generated code authenticates the model passthrough and the MCP tool servers
with a gateway **API key**, read from an environment variable
(`AI_GATEWAY_API_KEY`) and never hardcoded. Scaffolded projects keep `.env` out of
source control. If a key is ever exposed, rotate it in the [AI Gateway Portal](https://ai.gateway.azure.com).

Standalone agent scaffolds use least-privilege tool configuration: only explicitly
selected MCP tools are made available, and permission-requiring operations require
an explicit user decision. Generated applications do not automatically approve
tool requests. Review each requested operation and grant the application and its
gateway credentials only the permissions it needs.

To report a security issue, see [SECURITY.md](SECURITY.md).

## Samples

Browse the [samples catalog](samples/README.md) for application examples, or the
[Terraform architecture views](samples/terraform/README.md#architecture-views)
to understand the infrastructure before using the deployment guide.

## Contributing

For local Cursor plugin testing, symlink the repository into
`~/.cursor/plugins/local/ai-gateway` and reload the window.

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
