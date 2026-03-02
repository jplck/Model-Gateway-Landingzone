# Model Gateway Landing Zone

Hub-and-spoke architecture on Azure providing a central AI model gateway (API Management) with observability, fronting Azure AI Foundry backends. Spokes consume models via the hub and host workloads on Container Apps.

![Architecture](arch.png)

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) ≥ 2.67
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) ≥ 1.11
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) ≥ 0.30
- An Azure subscription with **Contributor** access
- Quota for Azure OpenAI models (e.g., GPT-4o) in the target region

## Quick Start

```bash
# 1. Clone the repository
git clone git@github.com:jplck/aigw_lz.git
cd aigw_lz

# 2. Log in to Azure
azd auth login
az login

# 3. Initialize environment
azd init -e dev

# 4. Set required environment variables
azd env set AZURE_LOCATION swedencentral
azd env set APIM_PUBLISHER_EMAIL your-email@company.com

# 5. Deploy everything
azd up
```

Deployment takes approximately **45–60 minutes** (APIM Developer SKU alone takes ~30 min).

## What Gets Deployed

### Hub (`rg-aigw-hub-{env}`)

| Resource | Purpose |
|---|---|
| Virtual Network | Hub networking with APIM, PE, and Agent subnets |
| Private DNS Zones (6) | Name resolution for private endpoints |
| Log Analytics + App Insights | Central observability stack |
| AI Foundry (AI Services) | Model hosting with capability hosts pattern |
| Storage Account | File storage for agents |
| AI Search | Vector storage for agents |
| Cosmos DB (Serverless) | Thread / message storage for agents |
| API Management | Model gateway with OpenAI-compatible API |
| Private Endpoints | Secure connectivity for all PaaS services |

### Spoke (`rg-aigw-spoke-{env}`)

| Resource | Purpose |
|---|---|
| Virtual Network | Spoke networking, peered to hub |
| Container Registry | Image storage for workload containers |
| Container Apps Environment | Agent / app hosting platform |
| Sample Container App | Placeholder app wired to APIM gateway |

### Optional: Spoke Foundry

When `deploySpokeFoundry=true`, a second AI Foundry instance is deployed in the spoke with a gateway connection back to the hub APIM. This enables Foundry Agent Service in the spoke to use hub-managed models.

```bash
azd env set DEPLOY_SPOKE_FOUNDRY true
azd up
```

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `location` | `swedencentral` | Azure region |
| `environmentName` | `dev` | Environment name |
| `projectName` | `aigw` | Resource naming prefix |
| `deploySpokeFoundry` | `false` | Deploy spoke Foundry with Agent Service |
| `publisherEmail` | `admin@contoso.com` | APIM publisher email |
| `publisherName` | `AI Gateway Team` | APIM publisher name |
| `hubModelDeployments` | `[gpt-4o]` | Models to deploy on hub Foundry |

## Testing the Gateway

After deployment, test inference through the APIM gateway:

```bash
# Get the APIM gateway URL and subscription key
APIM_URL=$(az apim show -n <apim-name> -g rg-aigw-hub-dev --query gatewayUrl -o tsv)
SUB_KEY=$(az rest --method post \
  --url "https://management.azure.com/subscriptions/{sub}/resourceGroups/rg-aigw-hub-dev/providers/Microsoft.ApiManagement/service/{apim}/subscriptions/spoke-subscription/listSecrets?api-version=2024-05-01" \
  --query primaryKey -o tsv)

# Call chat completions
curl -X POST "${APIM_URL}/openai/deployments/gpt-4o/chat/completions?api-version=2024-10-21" \
  -H "api-key: ${SUB_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'
```

## Repository Structure

```
├── azure.yaml                          # azd project definition
├── infra/
│   ├── main.bicep                      # Subscription-scoped orchestrator
│   ├── main.bicepparam                 # Parameters file
│   └── modules/
│       ├── hub/
│       │   ├── networking.bicep        # Hub VNet, subnets, NSGs
│       │   ├── dns.bicep               # Private DNS zones + VNet links
│       │   ├── observability.bicep     # Log Analytics + App Insights
│       │   ├── foundry.bicep           # AI Foundry (caphost pattern)
│       │   ├── apim.bicep              # API Management gateway
│       │   └── policies/
│       │       └── openai-api-policy.xml
│       ├── spoke/
│       │   ├── networking.bicep        # Spoke VNet, subnets, NSGs
│       │   └── container-apps.bicep    # ACR + Container Apps
│       ├── peering.bicep               # VNet peering helper
│       └── dns-zone-link.bicep         # DNS zone link helper
├── spec.md                             # Architecture specification
├── tasks.md                            # Implementation task list
└── arch.png                            # Architecture diagram
```

## Adding a Second Foundry Backend (Phase 5)

To add load balancing across multiple Foundry instances, deploy another Foundry module and update APIM:

1. Add a second `hubFoundry2` module call in `main.bicep` with `instanceSuffix: 'hub2'`
2. Register the new endpoint as an additional APIM backend
3. Update `openai-api-policy.xml` to use a backend pool with round-robin routing

## Security Hardening (Phase 9)

For production-like security:

1. Set `publicNetworkAccess: 'Disabled'` on all Foundry, Storage, Search, Cosmos DB resources
2. Set `networkAcls.defaultAction: 'Deny'` on Foundry accounts
3. Switch APIM to external VNet mode with `virtualNetworkType: 'External'`
4. Set Container Apps Environment `internal: true`
5. Configure Cosmos DB firewall to allow only Azure services and known IPs

## License

See [LICENSE](LICENSE).
