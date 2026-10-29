# Samples

A curated catalog of samples that build on the [AI Gateway tier in Azure API Management](https://aka.ms/aigateway/docs). Samples are linked from their own repositories, with a local Terraform infrastructure sample below.

| Sample | Language | Description |
| ------ | -------- | ----------- |
| Foundry AI Gateway E2E | [Python](https://aka.ms/foundry-aigateway-python) / [.NET (C#)](https://aka.ms/foundry-aigateway-dotnet) | A Daily Digest Agent deployed as a Foundry Hosted Agent whose model and GitHub MCP traffic is routed through AI Gateway. |
| IaC only | [Bicep](https://github.com/Azure-Samples/simple-foundry-hosted-agent-python-aigateway/tree/main/infra/ai-gateway) / [Terraform scenarios](terraform/README.md#choose-your-scenario) | AI Gateway, Foundry Models and hosted-agent infrastructure. Terraform supports **Public** and **Private-only** configurations, including optional private hosted-agent infrastructure. |

**Existing platform network and central DNS?** Use the
[Scenario 01 customer guide and file checklist](terraform/docs/scenarios/01-existing-network.md),
then its [filled input walkthrough](terraform/examples/filled/01-existing-network/README.md).
The external application samples above are not additional Terraform setup steps.
