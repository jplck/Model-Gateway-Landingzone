# Model Gateway Landing Zone — Task List

Derived from [spec.md](spec.md). Hub-and-spoke architecture on Azure: the hub provides a central model gateway (API Management) and observability; spokes consume models and host workloads.

---

## Phase 0 — Project Setup & Architecture

- [ ] **0.1** Set up Bicep repository scaffolding (folder structure, module layout, backend config)
- [ ] **0.2** Set up azd project (`azure.yaml`, environment config) for one-command demo deployment
- [ ] **0.3** Finalize architecture diagram (`arch.png`) — document hub and spoke resource layout, networking topology, and data flows
- [ ] **0.4** Define naming conventions and tagging strategy
- [ ] **0.5** Identify Azure subscriptions to use (hub subscription, spoke subscription(s), additional subscriptions for rate-limit balancing of Foundry backends)
- [ ] **0.6** Determine which spokes need Foundry Agent Service vs. plain inference-only access (impacts whether capability hosts and gateway-to-Foundry linking are required)

---

## Phase 1 — Hub Networking

- [ ] **1.1** Create hub virtual network with required subnets:
  - API Management subnet (dedicated, with NSG)
  - Private Endpoint subnet
  - Agent subnet delegated to `Microsoft.CognitiveServices/accounts` (required for hub Foundry capability hosts)
- [ ] **1.2** Create or link private DNS zones required by hub services:
  - `privatelink.cognitiveservices.azure.com`
  - `privatelink.openai.azure.com`
  - `privatelink.services.ai.azure.com`
  - `privatelink.blob.core.windows.net`
  - `privatelink.search.windows.net`
  - `privatelink.documents.azure.com` (if Cosmos DB / agents used)
- [ ] **1.3** Set up NSGs and route tables for hub subnets
- [ ] **1.4** Plan IP address space to accommodate future spokes without overlap

---

## Phase 2 — Hub Observability

- [ ] **2.1** Deploy Log Analytics workspace in the hub
- [ ] **2.2** Deploy Application Insights instance connected to the Log Analytics workspace
- [ ] **2.3** Configure diagnostic settings template so every hub resource sends logs/metrics to Log Analytics
- [ ] **2.4** Create initial Azure Monitor alert rules (availability, latency, error rate for gateway)
- [ ] **2.5** Build or import dashboards for central monitoring (API gateway metrics, model latency, token usage, error breakdown)

---

## Phase 3 — Hub Model Hosting (Azure AI Foundry Backends)

- [ ] **3.1** Deploy first Azure AI Foundry account + project (primary model host) using standard deployment with capability hosts ([caphost pattern](https://github.com/sramayanam/aifoundrylandingzone/blob/main/terraform-foundry-caphost/README.md)):
  - Configure `networkInjections` for agent subnet
  - Deploy Storage Account, AI Search, Cosmos DB (for threads)
  - Create private endpoints for all Foundry-related resources
  - Add RBAC assignments with 60-second propagation wait
  - Create account-level and project-level capability hosts
- [ ] **3.2** Deploy model(s) inside the first Foundry (e.g., GPT-4o, GPT-4o-mini) as model endpoints
- [ ] **3.3** Deploy additional Foundry account(s) in separate subscription(s) to balance rate limits — each using the same capability hosts pattern
- [ ] **3.4** Deploy model(s) in secondary Foundry instances
- [ ] **3.5** Create private endpoints for each Foundry so they are reachable from the hub VNet
- [ ] **3.6** (Optional) Add non-Azure model providers (hyperscalers / third-party) — document endpoint format and auth
- [ ] **3.7** Validate that all model endpoints respond to inference requests over private networking

---

## Phase 4 — Hub API Management (Model Gateway)

- [ ] **4.1** Deploy Azure API Management instance (Developer / Standard v2 / Premium depending on VNet integration needs)
- [ ] **4.2** Configure VNet integration for API Management (internal or external mode)
- [ ] **4.3** Register each Foundry model endpoint as an APIM backend (with managed identity or key-based auth)
- [ ] **4.4** Create APIM API definition(s) that expose the OpenAI-compatible inference endpoints (`/chat/completions`, `/completions`, `/embeddings`, etc.)
- [ ] **4.5** Implement APIM policies:
  - Load balancing / round-robin across multiple Foundry backends
  - Retry & circuit-breaker for backend failures
  - Rate limiting / quota per subscription key or caller identity
  - Token counting / usage tracking (emit to App Insights)
  - Request/response logging (sanitised)
  - Authentication (validate JWT / subscription key)
- [ ] **4.6** Configure APIM diagnostic settings to send logs and metrics to the hub Log Analytics / App Insights
- [ ] **4.7** Set up APIM products and subscription keys for spoke consumers
- [ ] **4.8** (If agent service used in spokes) Create gateway connection in spoke Foundry pointing to APIM — deploy connection using Bicep template per [AI Gateway docs](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/ai-gateway):
  - Choose connection type (APIM or Model Gateway)
  - Deploy connection via `az deployment group create`
  - Verify connection status shows Active in Foundry portal
- [ ] **4.9** Smoke-test inference through APIM from hub network (curl / SDK)

---

## Phase 5 — Spoke Networking & Connectivity

- [ ] **5.1** Create spoke virtual network with subnets:
  - Container Apps Environment subnet (minimum /23 recommended)
  - Private Endpoint subnet
  - (If Foundry with agents) Agent subnet delegated to `Microsoft.CognitiveServices/accounts`
- [ ] **5.2** Peer hub VNet ↔ spoke VNet (or use VNet gateway / VWAN if cross-subscription)
- [ ] **5.3** Link spoke VNet to hub private DNS zones (so spoke resources can resolve hub private endpoints)
- [ ] **5.4** Configure NSGs on spoke subnets — block direct public inbound access; only allow traffic via hub APIM
- [ ] **5.5** Validate private name resolution from spoke to hub Foundry / APIM endpoints

---

## Phase 6 — Spoke Foundry (Conditional)

> Only required if the spoke uses Foundry Agent Service.

- [ ] **6.1** Deploy Azure AI Foundry account + project in the spoke with capability hosts (following [aifoundrylandingzone caphost pattern](https://github.com/sramayanam/aifoundrylandingzone/blob/main/terraform-foundry-caphost/README.md)):
  - Configure `networkInjections` for agent subnet
  - Deploy Storage Account, AI Search, Cosmos DB (for threads)
  - Create private endpoints for all Foundry-related resources
  - Add RBAC assignments with 60-second propagation wait
  - Create account-level and project-level capability hosts
- [ ] **6.2** Create gateway connection from spoke Foundry to hub APIM (APIM or Model Gateway type)
- [ ] **6.3** Verify spoke Foundry agent can call models via `<connection-name>/<model-name>` format through hub APIM
- [ ] **6.4** Configure spoke Foundry diagnostic settings to send to hub Log Analytics

---

## Phase 7 — Spoke Container Apps & Registry

- [ ] **7.1** Deploy Azure Container Registry (ACR) in the spoke (or shared in hub)
- [ ] **7.2** Configure ACR private endpoint and DNS
- [ ] **7.3** Deploy Azure Container Apps Environment in the spoke subnet
- [ ] **7.4** Configure Container Apps Environment to use hub Log Analytics for logging
- [ ] **7.5** Deploy a sample container app that calls the hub APIM model gateway — validate end-to-end inference
- [ ] **7.6** Set up managed identity for container apps to authenticate against APIM (or use subscription key injection from Key Vault)
- [ ] **7.7** Configure autoscaling rules for container apps

---

## Phase 8 — Security Hardening

- [ ] **8.1** Ensure all data-plane traffic flows over private endpoints — no public endpoints exposed except APIM's external gateway (if external mode)
- [ ] **8.2** Disable public network access on Foundry accounts, Storage, Cosmos DB, ACR, AI Search
- [ ] **8.3** Configure Cosmos DB firewall: allow Azure services, whitelist development IPs
- [ ] **8.4** Enable managed identity authentication everywhere possible (APIM → Foundry, Container Apps → APIM, Foundry → Storage/Search/Cosmos)
- [ ] **8.5** Store secrets (API keys, connection strings) in Azure Key Vault; reference from APIM named values and Container Apps secrets
- [ ] **8.6** Enable Microsoft Defender for Cloud on subscriptions
- [ ] **8.7** Review and tighten NSG / firewall rules

---

## Phase 9 — Testing & Validation

- [ ] **9.1** End-to-end test: Container App in spoke → hub APIM → Foundry backend → model inference response
- [ ] **9.2** End-to-end test (if agents): Spoke Foundry Agent → hub APIM gateway connection → model inference
- [ ] **9.3** Validate load balancing: send traffic and confirm distribution across multiple Foundry backends
- [ ] **9.4** Validate failover: disable one backend, confirm APIM retries to healthy backend
- [ ] **9.5** Validate observability: check that request traces appear in App Insights and Log Analytics from both hub and spoke
- [ ] **9.6** Validate network isolation: confirm spokes cannot be reached from public internet except through hub APIM
- [ ] **9.7** Performance / load test to baseline latency and throughput

---

## Phase 10 — Documentation & Demo Readiness

- [ ] **10.1** Document architecture decision records (ADRs) for key choices
- [ ] **10.2** Write README with `azd up` quick-start instructions for demo deployment
- [ ] **10.3** Write runbook for common operations (add a new spoke, add a new model, rotate keys, scale backends)
- [ ] **10.4** Create cost estimate for the demo environment
- [ ] **10.5** Conduct architecture review / sign-off
