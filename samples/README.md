# Samples

A curated catalog of [AI Gateway](https://aka.ms/aigateway/docs) samples. This folder links to external sample repositories and includes the Terraform sample.

| Sample | Language | Description |
| ------ | -------- | ----------- |
| Foundry AI Gateway E2E | [Python](https://aka.ms/foundry-aigateway-python) / [.NET (C#)](https://aka.ms/foundry-aigateway-dotnet) | A Daily Digest Agent deployed as a Foundry Hosted Agent whose model and GitHub MCP traffic is routed through AI Gateway. |
| IaC only | [Bicep](https://github.com/Azure-Samples/simple-foundry-hosted-agent-python-aigateway/tree/main/infra/ai-gateway) / [Terraform](terraform/api2026gateway/README.md) | Provision AI Gateway, Foundry model deployments and agent-support infrastructure. **Bicep building blocks:** [AI Gateway](https://github.com/Azure-Samples/simple-foundry-hosted-agent-python-aigateway/tree/main/infra/ai-gateway), [Foundry Models](https://github.com/Azure-Samples/simple-foundry-hosted-agent-python-aigateway/tree/main/infra/foundry-models), and [Foundry Hosted Agent](https://github.com/Azure-Samples/simple-foundry-hosted-agent-python-aigateway/tree/main/infra/foundry-agents). **Terraform:** [deployment guide](terraform/api2026gateway/README.md) and [architecture](terraform/api2026gateway/architecture.md) for the experimental standalone gateway with authenticated public ingress. |
