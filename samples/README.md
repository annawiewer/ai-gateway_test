# Samples

A curated catalog of samples that build on the [AI Gateway tier in Azure API Management](https://aka.ms/aigateway/docs). This repository includes separate Terraform and Bicep/Python examples, alongside links to upstream application samples.

| Sample | Language | Description |
| ------ | -------- | ----------- |
| Foundry AI Gateway E2E | [Local Bicep/Python example](bicep/README.md) / [Upstream Python](https://aka.ms/foundry-aigateway-python) / [.NET (C#)](https://aka.ms/foundry-aigateway-dotnet) | A Daily Digest Agent deployed as a Foundry Hosted Agent whose model and GitHub MCP traffic is routed through AI Gateway. The local copy includes infrastructure, application, hooks, tests and its dependency lockfile. |
| IaC only | [Local Bicep gateway module](bicep/infra/ai-gateway/README.md) / [Terraform scenarios](terraform/README.md#choose-your-scenario) | AI Gateway, Foundry Models and hosted-agent infrastructure. Terraform supports **Public** and **Private-only** configurations, including optional private hosted-agent infrastructure. |

**Choose one deployment alternative.** The [Bicep snapshot](bicep/README.md#snapshot-in-this-test-repository)
uses the newer `aigateways/Consumption` resource and includes two open upstream
changes, one still a draft. Terraform retains its separate legacy
`service/AIGateway` contract and existing inputs. Adding the Bicep files does not
enable their policies in Terraform or migrate its resources. Do not deploy the
Bicep sample against resources managed by the Terraform stack.

**Existing platform network and central DNS?** Use the
[Scenario 01 customer guide and file checklist](terraform/docs/scenarios/01-existing-network.md),
then its [filled input walkthrough](terraform/examples/filled/01-existing-network/README.md).
The Bicep and external application samples above are not additional Terraform setup steps.
