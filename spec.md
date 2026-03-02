Model Gateway Landing Zone

This repository is meant to prove an architecture proposal. Find the planned architecture in arch.png. Overall idea is a hub and spoke architecture where the hub provides central observeability and a model gateway to access llm models with ai foundry and other hyperscalers or model providers. The spokes use the hub to consume models and to centralize monitoring and observeability.

General Tech Stack:

Bicep for IaC. Add azd for easier demo deployment. No pipelines required as no production deployment required. Make sure to have something working and deployable after each step.

Hub:
- Solution runs on Azure.
- Central Logging Monitoring is handled by Azure Monitor, App Insights
- Model Gateway uses API Gateway on Azure
- If Agent Service is used in Foundry, Model Gateway needs to be linked to Spoke foundries (see https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/ai-gateway)
- In any case the API gateway needs to expose model endpoints for inference
- Model hosting is done by multiple foundries. Potentially within different subscriptions to balance rate limits. Uses standard deployment with capability hosts (see https://github.com/sramayanam/aifoundrylandingzone/blob/main/terraform-foundry-caphost/README.md) The are exposed as backends in API GW
Spoke:
- Microsoft Foundry that consumes Model Gateway bring your own gateway (see above). Uses standard deployment with capability hosts (see https://github.com/sramayanam/aifoundrylandingzone/blob/main/terraform-foundry-caphost/README.md)
- If no agent service is used, no foundry mandatory
- Azure Container Apps as central agent hosting plattform
- Azure Container Registry

Networking needs to be provided between hub and spoke. Public access to the spokes should be only possible via the hub API Gateway