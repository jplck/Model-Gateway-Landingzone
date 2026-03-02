# Model Gateway Landing Zone — Task List

Derived from [spec.md](spec.md). Hub-and-spoke architecture on Azure: the hub provides a central model gateway (API Management) and observability; spokes consume models and host workloads.

> **Principle:** Each phase produces a deployable, working increment. After every phase you can run `azd up` (or the relevant Bicep deployment) and validate the result before moving on.

---

## Phase 1 — Project Scaffolding & azd Bootstrap

- [x] **1.1** Set up Bicep repository scaffolding (folder structure, module layout)
- [x] **1.2** Set up azd project (`azure.yaml`, environment config) — verify `azd up` runs (even if it deploys nothing yet)
- [x] **1.3** Finalize architecture diagram (`arch.png`) — document hub/spoke resource layout, networking topology, and data flows
- [x] **1.4** Define naming conventions and tagging strategy
- [x] **1.5** Identify Azure subscriptions (hub, spoke(s), extra subs for rate-limit balancing)
- [x] **1.6** Determine which spokes need Foundry Agent Service vs. inference-only access

**Deployable checkpoint:** `azd up` succeeds with empty/skeleton deployment.

---

## Phase 2 — Hub Foundation (Networking + Observability)

- [x] **2.1** Create hub resource group
- [x] **2.2** Create hub virtual network with subnets:
  - API Management subnet (dedicated, with NSG)
  - Private Endpoint subnet
  - Agent subnet delegated to `Microsoft.CognitiveServices/accounts`
- [x] **2.3** Create private DNS zones:
  - `privatelink.cognitiveservices.azure.com`
  - `privatelink.openai.azure.com`
  - `privatelink.services.ai.azure.com`
  - `privatelink.blob.core.windows.net`
  - `privatelink.search.windows.net`
  - `privatelink.documents.azure.com`
- [x] **2.4** Set up NSGs and route tables for hub subnets
- [x] **2.5** Deploy Log Analytics workspace
- [x] **2.6** Deploy Application Insights connected to the Log Analytics workspace

**Deployable checkpoint:** `azd up` deploys hub VNet, DNS zones, and observability stack. Validate subnets, DNS zone links, and App Insights ingestion.

---

## Phase 3 — Hub Foundry (First Model Backend)

- [x] **3.1** Deploy first Azure AI Foundry account + project using standard deployment with capability hosts ([caphost pattern](https://github.com/sramayanam/aifoundrylandingzone/blob/main/terraform-foundry-caphost/README.md)):
  - Configure `networkInjections` for agent subnet
  - Deploy Storage Account, AI Search, Cosmos DB (for threads)
  - Create private endpoints for all Foundry-related resources
  - Add RBAC assignments with 60-second propagation wait
  - Create account-level and project-level capability hosts
- [x] **3.2** Deploy model(s) inside the Foundry (e.g., GPT-4o, GPT-4o-mini)
- [x] **3.3** Configure Foundry diagnostic settings → hub Log Analytics
- [x] **3.4** Validate: call model endpoint directly from within the hub VNet

**Deployable checkpoint:** `azd up` adds Foundry + model. Direct inference call succeeds over private networking.

---

## Phase 4 — Hub API Management (Model Gateway)

- [x] **4.1** Deploy Azure API Management instance (Developer / Standard v2 / Premium)
- [x] **4.2** Configure VNet integration for APIM (internal or external mode)
- [x] **4.3** Register the Foundry model endpoint as an APIM backend (managed identity or key-based auth)
- [x] **4.4** Create APIM API definition(s) exposing OpenAI-compatible inference endpoints (`/chat/completions`, `/completions`, `/embeddings`, etc.)
- [x] **4.5** Implement APIM policies:
  - Authentication (validate JWT / subscription key)
  - Request/response logging (sanitised) → App Insights
  - Rate limiting / quota per subscription key or caller identity
- [x] **4.6** Configure APIM diagnostic settings → hub Log Analytics / App Insights
- [x] **4.7** Set up APIM products and subscription keys for spoke consumers
- [x] **4.8** Validate: smoke-test inference through APIM (curl / SDK)

**Deployable checkpoint:** `azd up` adds APIM gateway. Inference via APIM returns model response; logs appear in App Insights.

---

## Phase 5 — Hub Multi-Backend & Load Balancing

- [x] **5.1** Deploy additional Foundry account(s) in separate subscription(s) using same capability hosts pattern
- [x] **5.2** Deploy model(s) in secondary Foundry instances
- [x] **5.3** Create private endpoints for secondary Foundries → hub VNet
- [x] **5.4** Register secondary Foundries as additional APIM backends
- [x] **5.5** Add APIM policies:
  - Load balancing / round-robin across backends
  - Retry & circuit-breaker for backend failures
  - Token counting / usage tracking (emit to App Insights)
- [x] **5.6** (Optional) Add non-Azure model providers (hyperscalers / third-party) as APIM backends
- [x] **5.7** Validate: send traffic and confirm distribution across backends; disable one backend and confirm failover

**Deployable checkpoint:** `azd up` adds secondary backends. Load balancing and failover verified.

---

## Phase 6 — Spoke Networking & Peering

- [x] **6.1** Create spoke resource group
- [x] **6.2** Create spoke virtual network with subnets:
  - Container Apps Environment subnet (minimum /23 recommended)
  - Private Endpoint subnet
  - (If Foundry with agents) Agent subnet delegated to `Microsoft.CognitiveServices/accounts`
- [x] **6.3** Peer hub VNet ↔ spoke VNet (or VNet gateway / VWAN if cross-subscription)
- [x] **6.4** Link spoke VNet to hub private DNS zones
- [x] **6.5** Configure NSGs on spoke subnets — block direct public inbound; allow traffic via hub APIM only
- [x] **6.6** Validate: private name resolution from spoke to hub APIM / Foundry endpoints

**Deployable checkpoint:** `azd up` adds spoke VNet with peering. DNS resolution and connectivity to hub verified.

---

## Phase 7 — Spoke Container Apps & Registry

- [x] **7.1** Deploy Azure Container Registry (ACR) in the spoke (or shared in hub)
- [x] **7.2** Configure ACR private endpoint and DNS
- [x] **7.3** Deploy Azure Container Apps Environment in the spoke subnet
- [x] **7.4** Configure Container Apps Environment → hub Log Analytics for logging
- [x] **7.5** Set up managed identity for container apps to authenticate against APIM (or subscription key via Key Vault)
- [x] **7.6** Deploy a sample container app that calls hub APIM model gateway
- [x] **7.7** Validate: end-to-end inference Container App → hub APIM → Foundry → response

**Deployable checkpoint:** `azd up` adds ACR + Container Apps. Sample app successfully calls model through gateway.

---

## Phase 8 — Spoke Foundry (Conditional — Agent Service)

> Only required if the spoke uses Foundry Agent Service.

- [x] **8.1** Deploy Azure AI Foundry account + project in the spoke with capability hosts ([caphost pattern](https://github.com/sramayanam/aifoundrylandingzone/blob/main/terraform-foundry-caphost/README.md)):
  - Configure `networkInjections` for agent subnet
  - Deploy Storage Account, AI Search, Cosmos DB (for threads)
  - Create private endpoints for all Foundry-related resources
  - Add RBAC assignments with 60-second propagation wait
  - Create account-level and project-level capability hosts
- [x] **8.2** Create gateway connection from spoke Foundry to hub APIM (APIM or Model Gateway type) per [AI Gateway docs](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/ai-gateway)
- [x] **8.3** Configure spoke Foundry diagnostic settings → hub Log Analytics
- [x] **8.4** Validate: spoke Foundry agent calls models via `<connection-name>/<model-name>` through hub APIM

**Deployable checkpoint:** `azd up` adds spoke Foundry with agent service. Agent inference through gateway verified.

---

## Phase 9 — Security Hardening & Final Validation

- [x] **9.1** Disable public network access on Foundry accounts, Storage, Cosmos DB, ACR, AI Search
- [x] **9.2** Ensure all data-plane traffic flows over private endpoints — only APIM external gateway exposed publicly
- [x] **9.3** Configure Cosmos DB firewall: allow Azure services, whitelist development IPs
- [x] **9.4** Enable managed identity authentication everywhere (APIM → Foundry, Container Apps → APIM, Foundry → Storage/Search/Cosmos)
- [x] **9.5** Store any remaining secrets in Azure Key Vault; reference from APIM named values and Container Apps secrets
- [x] **9.6** Validate: confirm spokes unreachable from public internet except through hub APIM
- [x] **9.7** Validate: full observability — request traces in App Insights from hub and spoke
- [x] **9.8** Validate: load test to baseline latency and throughput

**Deployable checkpoint:** `azd up` deploys hardened environment. All E2E tests pass with private networking enforced.

---

## Phase 10 — Documentation & Demo Readiness

- [x] **10.1** Write README with `azd up` quick-start instructions for demo deployment
- [x] **10.2** Document architecture decision records (ADRs) for key choices
- [x] **10.3** Write runbook for common operations (add a new spoke, add a new model, rotate keys, scale backends)
- [x] **10.4** Create cost estimate for the demo environment
- [x] **10.5** Conduct architecture review / sign-off

**Deployable checkpoint:** Repository is self-documenting; a new user can `azd up` from the README and have a working environment.
