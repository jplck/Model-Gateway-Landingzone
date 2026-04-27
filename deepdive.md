# AI Gateway Landing Zone — Architecture Deep Dive

## Overview

This repository implements a **hub-spoke AI Gateway Landing Zone** on Azure. The central idea is to place Azure API Management (APIM) in the hub as a **model gateway** that fronts Azure AI Foundry model endpoints, while spoke teams deploy their applications into isolated Container Apps environments and consume AI models exclusively through the gateway.

The entire infrastructure is defined in Bicep, deployed via `scripts/deploy.sh` (a phased Azure CLI orchestrator), and follows a phased approach where each phase can be deployed incrementally.

The chat agent application offers **two modes** of AI interaction, with Entra Agent Identity and A365 observability (preview):

1. **LangGraph Agent** — LangGraph ReAct agent with tools → APIM → Hub Foundry (API key or Agent Identity auth)
2. **Foundry Agent** — PromptAgent SDK → Agent Service → APIM Gateway → Hub Foundry

Optional capabilities:
- **Entra Agent Identity** — Gives the agent its own security identity via Blueprint + Agent Identity + FIC + auth sidecar
- **A365 Observability (Preview)** — Automatic tracing of LangChain/LangGraph executions via the Microsoft Agent 365 SDK
- **Spoke Storage** — Blob storage accessible via Agent Identity tokens, with a `list_files` tool for the LangGraph agent

```
┌──────────────────────────────────────────────────────────────────────┐
│  Internet                                                            │
│      │                                                               │
│      ▼                                                               │
│  ┌────────────────────── Hub VNet (10.0.0.0/16) ──────────────────┐  │
│  │                                                                 │  │
│  │  ┌─────────────────────────────────────┐                        │  │
│  │  │ APIM (External VNet Integration)    │                        │  │
│  │  │ snet-apim (10.0.1.0/24)            │                        │  │
│  │  │                                     │                        │  │
│  │  │  /openai/* → Foundry (MI auth)      │                        │  │
│  │  │  /chat/*  → Spoke Container App     │──── via PE ────┐      │  │
│  │  └─────────────────────────────────────┘                │      │  │
│  │                                                          │      │  │
│  │  ┌─────────────────────────────────────┐                │      │  │
│  │  │ Private Endpoints (hub services)    │                │      │  │
│  │  │ snet-pe (10.0.2.0/24)              │                │      │  │
│  │  │  • AI Services  • Storage           │                │      │  │
│  │  │  • AI Search    • Cosmos DB         │                │      │  │
│  │  └─────────────────────────────────────┘                │      │  │
│  │                                                          │      │  │
│  │  ┌─────────────────────────────────────┐                │      │  │
│  │  │ AI Foundry (Cognitive Services)     │                │      │  │
│  │  │  • gpt-4o (GlobalStandard, 10 TPM) │                │      │  │
│  │  │  • Capability Host pattern          │                │      │  │
│  │  └─────────────────────────────────────┘                │      │  │
│  │                                                          │      │  │
│  │  Private DNS Zones (7 zones, linked to both VNets)      │      │  │
│  │  Observability (Log Analytics + App Insights)           │      │  │
│  └────────────────────── VNet Peering ─────────────────────┼──┐   │  │
│                                                             │  │   │  │
│  ┌────────────────────── Spoke VNet (10.1.0.0/16) ─────────┼──┼─┐ │  │
│  │                                                          │  │ │ │  │
│  │  ┌─────────────────────────────────────┐                │  │ │ │  │
│  │  │ Container Apps Environment          │                │  │ │ │  │
│  │  │ snet-container-apps (10.1.0.0/23)  │                │  │ │ │  │
│  │  │ publicNetworkAccess: Disabled       │                │  │ │ │  │
│  │  │                                     │                │  │ │ │  │
│  │  │  ┌───────────────────────────────┐  │                │  │ │ │  │
│  │  │  │ Chat Agent (LangGraph+FastAPI) │  │                │  │ │ │  │
│  │  │  │ + Auth Sidecar (optional)      │◄─┼────────────────┘  │ │ │  │
│  │  │  │ Calls APIM /openai server-side │  │                   │ │ │  │
│  │  │  └───────────────────────────────┘  │                   │ │ │  │
│  │  └─────────────────────────────────────┘                   │ │ │  │
│  │                                                             │ │ │  │
│  │  ┌─────────────────────────────────────┐                   │ │ │  │
│  │  │ Spoke AI Foundry (Agent Service)    │                   │ │ │  │
│  │  │  • apim-gateway → APIM /openai      │                   │ │ │  │
│  │  │  • Account + project cap hosts       │                   │ │ │  │
│  │  └─────────────────────────────────────┘                   │ │ │  │
│  │                                                             │ │ │  │
│  │  ┌─────────────────────────────────────┐                   │ │ │  │
│  │  │ Private Endpoint (CAE)              │                   │ │ │  │
│  │  │ snet-pe (10.1.2.0/24) → 10.1.2.4   │◄──────────────────┘ │ │  │
│  │  └─────────────────────────────────────┘                     │ │  │
│  │                                                               │ │  │
│  │  ACR (Basic SKU, cloud builds via ACR Tasks)                  │ │  │
│  └───────────────────────────────────────────────────────────────┘ │  │
│                                                                     │  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Deployment Phases

Deployment is orchestrated by `scripts/deploy.sh`, which runs the Bicep templates as numbered phases. Each phase is a separate deployment; later phases can be skipped during incremental rollouts.

| Phase | Template | Purpose |
|-------|----------|---------|
| 1 | `infra/networking.bicep` | Hub + spoke VNets, subnets, NSGs, peering, private DNS zones |
| 2 | `infra/hub.bicep` | Observability (Log Analytics + App Insights), Foundry hub (account, project, caphost, model deployments), APIM with OpenAI API |
| 3 | `infra/spoke.bicep` | ACR, Container Apps Environment + chat agent app, optional spoke Foundry (Agent Service) |
| 4 | `infra/connectivity.bicep` | Foundry private endpoints, APIM Chat API (`/chat/*` → spoke app), CAE DNS wildcard, cross-resource RBAC |
| 5 | *(placeholder)* | Multi-backend load balancing — add more Foundry instances behind APIM |

---

## Network Architecture

### Hub VNet (`10.0.0.0/16`)

| Subnet | CIDR | Purpose | Notes |
|--------|------|---------|-------|
| `snet-apim` | `10.0.1.0/24` | APIM VNet integration | Delegated to `Microsoft.Web/serverFarms`, NSG allows 443, 3443, 6390 |
| `snet-pe` | `10.0.2.0/24` | Private endpoints | AI Services, Storage, Search, Cosmos DB |
| `snet-agent` | `10.0.3.0/24` | AI Foundry agent subnet | Delegated to `Microsoft.App/environments` |

### Spoke VNet (`10.1.0.0/16`)

| Subnet | CIDR | Purpose | Notes |
|--------|------|---------|-------|
| `snet-container-apps` | `10.1.0.0/23` | Container Apps Environment | Delegated to `Microsoft.App/environments`, /23 minimum |
| `snet-pe` | `10.1.2.0/24` | Private endpoints | CAE Private Endpoint (IP: `10.1.2.4`), spoke Foundry PEs |
| `snet-agent` | `10.1.3.0/27` | Spoke Foundry agent | Conditional, only when `deploySpokeFoundry=true` |

### VNet Peering

Bidirectional peering between hub and spoke:
- `peer-spoke-to-hub` (spoke → hub): Allows spoke apps to call APIM
- `peer-hub-to-spoke` (hub → spoke): Allows APIM to reach spoke container apps via PE

Both sides set `allowVirtualNetworkAccess: true` and `allowForwardedTraffic: true`.

### NSG Hardening

The spoke Container Apps subnet has a `Deny-Internet-Inbound` rule at priority 1000, blocking all public internet traffic at the network level.

---

## Private DNS Architecture

Seven private DNS zones are created in the hub resource group and linked to **both** VNets so that resources in either VNet resolve private endpoint IPs:

| DNS Zone | Service |
|----------|---------|
| `privatelink.cognitiveservices.azure.com` | AI Services |
| `privatelink.openai.azure.com` | OpenAI |
| `privatelink.services.ai.azure.com` | AI Services (new) |
| `privatelink.blob.core.windows.net` | Storage |
| `privatelink.search.windows.net` | AI Search |
| `privatelink.documents.azure.com` | Cosmos DB |
| `privatelink.<region>.azurecontainerapps.io` | Container Apps Environment |

### The Wildcard DNS Problem

When `publicNetworkAccess: 'Disabled'` is set on a Container Apps Environment and a Private Endpoint is created, the PE DNS zone group auto-creates an A record only for the **environment domain prefix** (e.g., `kindcoast-7b175670`). However, individual container app FQDNs are subdomains of this prefix:

```
ca-sample-aigw-aigw2.kindcoast-7b175670.swedencentral.azurecontainerapps.io
                     └── env prefix ──┘
```

Without a wildcard record, APIM resolves the app FQDN via public DNS (getting the public IP), and the request fails with `403 — public network access disabled`.

The `cae-dns-wildcard.bicep` module solves this by creating:

```
*.kindcoast-7b175670  →  10.1.2.4  (PE private IP)
```

This ensures **any** container app in the environment resolves to the private endpoint IP from inside the VNet.

---

## APIM as Model Gateway

### VNet Integration (External Mode)

APIM StandardV2 is deployed with `virtualNetworkType: 'External'`, which:
- Places APIM's data plane inside `snet-apim` in the hub VNet
- Keeps the public gateway URL (`https://apim-xxx.azure-api.net`) accessible from the internet
- Enables APIM to resolve private DNS zones linked to the hub VNet
- Allows APIM to reach spoke resources via VNet peering + private endpoints

### OpenAI API (`/openai/*`)

The primary API exposes OpenAI-compatible endpoints:

| Operation | Method | URL Template |
|-----------|--------|-------------|
| Responses | POST | `/openai/deployments/{deployment-id}/responses` |
| Embeddings | POST | `/openai/deployments/{deployment-id}/embeddings` |
| List Deployments | GET | `/openai/deployments` |
| Get Deployment | GET | `/openai/deployments/{deployment-id}` |

**Authentication flow:**
1. Spoke consumer sends request with `api-key` header (APIM subscription key)
2. APIM validates the subscription key
3. APIM policy acquires a managed identity token for `https://cognitiveservices.azure.com`
4. Policy replaces `api-key` header with `Authorization: Bearer <MI-token>`
5. Request is forwarded to the Foundry backend

**Key policy features** (defined in `openai-api-policy.xml`):
- `authentication-managed-identity` — zero-credential auth to Foundry
- `set-header` — strips client key, injects MI bearer token
- `set-query-parameter` — defaults `api-version` to `2024-10-21`
- `rate-limit` — 100 calls/minute per subscription
- `set-backend-service` — routes to `foundry-backend`

### Chat API (`/chat/*`)

A separate API exposes the spoke chat agent through the hub gateway:

| Operation | Method | URL Template | Purpose |
|-----------|--------|-------------|---------|
| Get Chat Frontend | GET | `/` | Serves the HTML chat UI |
| Health Check | GET | `/health` | Returns health + config status |
| Chat API | POST | `/api/chat` | Direct inference (OpenAI SDK) |
| List Models | GET | `/api/models` | Dynamic model discovery |
| Agent Chat API | POST | `/api/agent/chat` | Foundry Agent (PromptAgent SDK) |
| Static Assets | GET | `/static/*` | CSS/JS assets for the UI |

**No subscription required** — the chat frontend is publicly accessible through APIM. The chat agent authenticates to APIM's OpenAI API server-side using its own subscription key.

The APIM policy sets `backend-id="chat-app-backend"`, which points to `https://<container-app-fqdn>`. CORS is enabled for browser access.

### Product & Subscription

A `model-gateway` product groups the OpenAI API. A `spoke-subscription` provides the key that spoke apps use. This key is injected as a secret into the container app environment.

---

## AI Foundry (Capability Host Pattern)

The Foundry module (`hub/foundry-core.bicep`) is **reusable** for both hub and spoke deployments via the `instanceSuffix` parameter. It deploys the full Azure AI Foundry stack:

```
AI Services Account (Microsoft.CognitiveServices/accounts, kind: AIServices)
  ├── gpt-4o deployment (hub only — spoke uses hub models via APIM)
  ├── Account-level Capability Host
  │     └── capabilityHostKind: 'Agents'
  ├── APIM Gateway Connection (spoke only — apim-gateway)
  └── AI Foundry Project (accounts/projects)
       ├── Project-level Capability Host
       │     ├── vectorStoreConnections → AI Search
       │     ├── storageConnections → Storage
       │     └── threadStorageConnections → Cosmos DB
       ├── Connections:
       │     ├── Storage (AzureStorageAccount, AAD auth)
       │     ├── AI Search (CognitiveSearch, AAD auth)
       │     ├── Cosmos DB (CosmosDB, AAD auth)
       │     └── App Insights (AppInsights, ApiKey auth) — conditional
       └── RBAC assignments (6 total — project + account identities → backing resources)
```

### Two Capability Host Levels

1. **Account-level** (`Microsoft.CognitiveServices/accounts/capabilityHosts@2025-10-01-preview`) — Deployed for the spoke Foundry. Wires the agent service for the project-level capability host below.

2. **Project-level** (`Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview`) — Always deployed. Wires the storage, search, and cosmos connections for Agent Service. Depends on the account-level host.

### Supporting Resources

- **Storage Account** — StorageV2, Standard_LRS, HTTPS only
- **AI Search** — Basic SKU, 1 replica, 1 partition
- **Cosmos DB** — Serverless, NoSQL, Session consistency

### Private Endpoints (4 per Foundry instance)

| Service | PE Group | DNS Zones |
|---------|----------|-----------|
| AI Services | `account` | cognitiveservices, openai, aiservices (3 zones) |
| Storage | `blob` | blob (1 zone) |
| AI Search | `searchService` | search (1 zone) |
| Cosmos DB | `Sql` | cosmos (1 zone) |

### RBAC Assignments

| Role | Scope | Principal |
|------|-------|-----------|
| Storage Blob Data Contributor | Storage Account | Project identity |
| Search Index Data Contributor | AI Search | Project identity |
| Search Service Contributor | AI Search | Project identity |
| Cosmos DB Operator | Cosmos DB | Project identity |
| Cosmos DB Data Contributor (SQL) | Cosmos DB | Project identity |
| Cosmos DB Data Contributor (SQL) | Cosmos DB | AI Services account identity |

### Spoke-Only Connections

When deployed as a spoke Foundry (`!empty(apimGatewayUrl)`):

1. **APIM Gateway Connection** (`category: ApiManagement`) — registered on the **account** (not project). Points to `${apimGatewayUrl}/openai`. Uses API key auth with the APIM subscription key. Metadata: `deploymentInPath: 'true'`, `provider: 'AzureOpenAI'`. Enables dynamic model discovery — no static model list needed.

---

## Spoke: Container Apps Environment

### Network Isolation

The Container Apps Environment is deployed with:

```bicep
publicNetworkAccess: 'Disabled'  // blocks all public internet traffic
internal: false                   // apps can receive traffic from outside the CAE
                                  // (but only via the Private Endpoint)
```

**Important distinction:** `internal` on the CAE's `vnetConfiguration` controls whether apps accept traffic from *outside the Container Apps Environment* (not outside the VNet). Setting it to `false` is correct — we want APIM to reach apps, just not from the public internet.

`publicNetworkAccess: 'Disabled'` is the environment-level control that blocks public traffic. Access is only possible via the Private Endpoint.

### Private Endpoint

A Private Endpoint for the CAE is created in `snet-pe` (spoke, `10.1.2.0/24`):

```
PE (pe-cae-aigw-aigw2)
  → NIC (nic-pe-cae-aigw-aigw2, IP: 10.1.2.4)
  → privateDnsZoneGroup → privatelink.<region>.azurecontainerapps.io
```

The `customNetworkInterfaceName` is set on the PE so the NIC can be referenced in Bicep to extract the private IP address. This IP is then passed to the wildcard DNS module.

### Container App

The chat agent app (`ca-sample-aigw-aigw2`) runs with:

| Setting | Value |
|---------|-------|
| Image | `acraigw....azurecr.io/chat-agent:v{timestamp}` (built via ACR Tasks) |
| Port | 8000 |
| CPU / Memory | 0.5 vCPU / 1 GiB |
| Min / Max replicas | 1 / 3 |
| Ingress | `external: true` (within CAE), via APIM only |
| Identity | SystemAssigned (used for ACR Pull, Foundry Agent SDK) |

**Environment variables:**

| Env Var | Source | Always |
|---------|--------|--------|
| `APIM_GATEWAY_URL` | Bicep param | Yes |
| `OPENAI_API_BASE` | `${apimGatewayUrl}/openai` | Yes |
| `OPENAI_DEPLOYMENT_NAME` | Hardcoded `gpt-4o` | Yes |
| `GATEWAY_CONNECTION_NAME` | Bicep param (default `apim-gateway`) | Yes |
| `APIM_API_KEY` | Secret ref `apim-api-key` | Conditional |
| `AI_PROJECT_ENDPOINT` | Spoke Foundry project endpoint | Conditional |

### Azure Container Registry

ACR Basic SKU with admin disabled. The container app's system-assigned managed identity has `AcrPull` role. Images are built via **ACR Tasks** (cloud build) — no local Docker required:

```bash
az acr build --registry <acr-name> --image chat-agent:latest ./apps/chat-agent
```

---

## Chat Agent Application

### Architecture

The chat agent (`apps/chat-agent`) is a **FastAPI** server (v4.0.0) split into four modules:

| File | Responsibility |
|------|----------------|
| `config.py` | All environment variable reads |
| `inference.py` | LangGraph ReAct agent, AzureChatOpenAI LLM, `list_files` tool, blob storage helper |
| `foundry_agent.py` | Foundry Agent Service integration (lazy SDK init) |
| `main.py` | FastAPI routes, A365 observability setup |

| Route | Method | Purpose | SDK |
|-------|--------|---------|-----|
| `/` | GET | Chat UI (static HTML with tab interface) | — |
| `/health` | GET | Health check + configuration status | — |
| `/api/models` | GET | Dynamic model discovery via APIM gateway | httpx |
| `/api/chat` | POST | LangGraph agent with tool calling | langchain-openai, langgraph |
| `/api/agent/chat` | POST | Foundry Agent (PromptAgent) | azure-ai-projects |
| `/api/files` | GET | List blobs in spoke storage | httpx + sidecar |
| `/api/auth/test` | GET | Probe auth sidecar tokens | httpx |

### Mode 1: LangGraph Agent (`/api/chat`)

Uses **LangGraph** (`create_react_agent`) with **AzureChatOpenAI** from `langchain-openai`. The agent automatically invokes tools (like `list_files`) when needed and returns tool call details alongside the response for UI display.

The model deployment can be overridden per-request. When Agent Identity is enabled, the `list_files` tool uses the auth sidecar to get a Storage token and lists blobs via the Azure Blob REST API.

The app authenticates to APIM with a subscription key, and APIM authenticates to Foundry with managed identity. The app never has direct access to Foundry credentials.

### Mode 2: Foundry Agent (`/api/agent/chat`)

Uses the **Azure AI Projects SDK** (`AIProjectClient` + `PromptAgentDefinition`) to create prompt-based agents via the Foundry Agent Service. Multi-turn conversations are supported via `previous_response_id`.

```python
# Lazy-init project client
client = AIProjectClient(endpoint=AI_PROJECT_ENDPOINT, credential=DefaultAzureCredential())
oai = client.get_openai_client()

# Create or cache a PromptAgent for the selected model
model_ref = f"{GATEWAY_CONNECTION_NAME}/{req.model}"  # e.g. "apim-gateway/gpt-4o"
agent = client.agents.create_version(
    agent_name=f"chat-{safe_name}",
    definition=PromptAgentDefinition(model=model_ref, instructions="..."),
)

# Invoke via Responses API with agent_reference
conv = oai.responses.create(
    model=model_ref,
    input=req.message,
    extra_body={"agent_reference": {"name": agent.name, "type": "agent_reference"}},
)
```

The `connectionName/modelName` format (e.g., `apim-gateway/gpt-4o`) tells Foundry to route the call through the APIM gateway connection rather than looking for a local deployment.

Multi-turn conversations are supported via `previous_response_id`.

### Chat UI

The HTML frontend (`static/index.html`) provides:
- **Two-tab interface**: Direct Inference, Foundry Agent
- **Model selector** (agent tab): Dynamic discovery via `/api/models`
- Multi-turn conversation with per-tab state
- Auto-resizing textarea
- Visual display of the current request flow path

---

## Request Flows

### Flow 1: Direct Inference (POST /api/chat)

```
Browser  →  POST APIM/chat/api/chat  {messages: [...]}
         →  APIM (no subscription required)  →  Container App POST /api/chat

Container App  →  OpenAI SDK (AzureOpenAI)
               →  POST APIM/openai/deployments/gpt-4o/responses
                   Header: api-key: <spoke-subscription-key>
               →  APIM validates subscription key
               →  APIM policy: acquires MI token for cognitiveservices.azure.com
               →  APIM policy: sets Authorization: Bearer <MI-token>
               →  APIM policy: rate-limit check (100/min)
               →  Forward to foundry-backend (AI Services endpoint)

AI Foundry  →  gpt-4o processes request  →  returns completion

Reverse path: AI Foundry → APIM → Container App → APIM /chat → Browser
```

### Flow 2: Foundry Agent (POST /api/agent/chat)

```
Browser  →  POST APIM/chat/api/agent/chat  {message, model, thread_id}
         →  Container App POST /api/agent/chat

Container App  →  AIProjectClient (DefaultAzureCredential)
               →  create_version() → PromptAgentDefinition(model="apim-gateway/gpt-4o")
               →  oai.responses.create(model, input, agent_reference)
               →  Spoke Foundry Agent Service
                    └── apim-gateway connection
                         └── APIM /openai/deployments/gpt-4o/...
                              └── Hub AI Services (gpt-4o)

Reverse path: Hub Foundry → APIM → Spoke Agent Service → Container App → APIM /chat → Browser
```

### DNS Resolution (APIM → Spoke Container App)

```
APIM resolves: ca-sample-aigw-aigw2.kindcoast-7b175670.swedencentral.azurecontainerapps.io

1. APIM uses hub VNet DNS (private DNS zones are linked)
2. CNAME chain: *.swedencentral.azurecontainerapps.io
   → *.kindcoast-7b175670.privatelink.swedencentral.azurecontainerapps.io
3. Private DNS zone lookup: *.kindcoast-7b175670 → 10.1.2.4 (wildcard A record)
4. APIM connects to 10.1.2.4 via VNet peering (hub → spoke)
5. Traffic arrives at PE NIC in snet-pe → forwarded to CAE
```

---

## CI/CD — Postprovision Hook

The `postprovision.sh` hook runs as the final phase of `scripts/deploy.sh` and handles capability-host creation plus the chat-agent image build & deploy:

```
scripts/deploy.sh
  └── Phase 1–4: Bicep deploys all infra (networking → hub → spoke → connectivity)
       └── Phase 5: postprovision.sh
            ├── 1. Create capability hosts (account + project) via REST polling
            │     └── hub Foundry (always) and spoke Foundry (if enabled)
            │
            └── 2. Build chat-agent image
                  ├── az acr build → chat-agent:v{timestamp}
                  ├── az containerapp update → deploy to spoke
                  ├── az containerapp ingress update → port 8000
                  └── azd env set CHAT_AGENT_IMAGE  (used as a local kv-store cache)
```

---

## Entra Agent Identity (Optional)

When enabled, the landing zone gives the chat agent its own Entra security identity — separate from the Container App's managed identity. This enables fine-grained, per-agent access control and supports two primary use cases:

### Use Cases

**Autonomous Agent** — The agent operates under its own security context. It authenticates as the Agent Identity and accesses Azure resources (storage, AI models) with RBAC roles assigned directly to the Agent Identity. No user involvement.

**On-Behalf-Of (Digital Colleague)** — The agent acts on behalf of a user, carrying the user's security context. An Agentic User (Digital Colleague) is created with its own mailbox, Teams presence, and calendar. Delegated permissions are consented on the Agent Identity, and the agent performs actions (reading mail, scheduling meetings) as the user's digital colleague. This requires additional Entra configuration (Agent User, delegated permission grants) beyond what this repository implements.

This landing zone demonstrates the **Autonomous Agent** pattern.

### Architecture

```
┌─────────────────────────────────────────────────────┐
│ Container App Pod                                    │
│                                                      │
│  ┌──────────────────┐    ┌────────────────────────┐ │
│  │   chat-agent      │    │   auth-sidecar         │ │
│  │   (port 8000)     │◄──►│   (port 8080)          │ │
│  │                   │    │                         │ │
│  │ • LangGraph agent │    │ • MI → FIC → Blueprint  │ │
│  │ • list_files tool │    │ • → Agent Identity      │ │
│  │ • A365 telemetry  │    │ • → Resource Token      │ │
│  └──────────────────┘    └────────────────────────┘ │
│                                                      │
│  System-Assigned Managed Identity                    │
└─────────────────────────────────────────────────────┘
```

### Token Flow

```
Container App MI → FIC → Blueprint → Agent Identity → Resource Token
```

The `fmi_path` parameter specifies which Agent Identity to impersonate. The final token's `oid` is the Agent Identity — Azure RBAC checks permissions against it, not the MI or Blueprint.

### Setup

The `setup_agent_identity.sh` script automates the full chain via Graph API:

1. Creates the Blueprint (`AgentIdentityBlueprint` app registration)
2. Creates the Blueprint Service Principal
3. Creates the Agent Identity (authenticating as the Blueprint with a temporary secret)
4. Creates a FIC linking the Container App MI to the Blueprint
5. Assigns RBAC roles (Storage Blob Data Contributor, Cognitive Services User) to the Agent Identity

The auth sidecar (`mcr.microsoft.com/entra-sdk/auth-sidecar`) runs alongside the app and exposes `GET /AuthorizationHeaderUnauthenticated/{apiName}?AgentIdentity={id}` for credential-free token acquisition.

### Spoke Storage

When Agent Identity is enabled, a spoke storage account with a blob container (`agent-files`) is provisioned. The `list_files` LangChain tool uses the sidecar to get a Storage token and lists blobs via the Azure Blob REST API. The LangGraph agent can invoke this tool automatically when users ask about files.

---

## A365 Observability (Preview)

> **Preview:** A365 observability is currently in preview. APIs and telemetry schemas may change.

The [Microsoft Agent 365 SDK](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-sdk?tabs=python) provides observability extensions that trace LangGraph agent executions end-to-end. The `/api/chat` route wraps each request in explicit A365 observability scopes, and `CustomLangChainInstrumentor` auto-instruments LangChain/LangGraph chains.

### Startup Configuration

A365 is configured at module load time in `main.py` when both `AGENTID_SIDECAR_URL` and `AGENT_IDENTITY_APP_ID` are set:

```python
a365_configure(
    service_name="chat-agent",
    service_namespace="aigw-landing-zone",
    token_resolver=_a365_token_resolver,
    cluster_category="prod",
)

CustomLangChainInstrumentor()
```

The `_a365_token_resolver` callback acquires an `AgentToken` from the auth sidecar at `{AGENTID_SIDECAR_URL}/AuthorizationHeaderUnauthenticated/AgentToken?AgentIdentity={id}` and strips the `Bearer ` prefix. This token authenticates telemetry export to the Agent365 backend.

If the A365 packages aren't installed (e.g., auth sidecar not enabled), the import fails gracefully and `_a365_available` is set to `False`. The app works normally without observability.

### Observability Scopes

Each `/api/chat` request is wrapped in nested scopes:

| Scope | Captured Data |
|---|---|
| `BaggageBuilder` | Correlation context — tenant ID, agent ID, correlation ID (UUID per request) |
| `InvokeAgentScope` | Full agent invocation — input/output messages, session ID |
| `InferenceScope` | LLM calls — model name, provider (`Azure OpenAI via APIM`), input/output token counts, finish reasons |
| `ExecuteToolScope` | Tool executions — tool name, arguments (JSON), result |

The scope nesting follows the execution flow:

```
BaggageBuilder (tenant_id, agent_id, correlation_id)
  └── InvokeAgentScope (invoke_details, tenant_details, request)
        ├── record_input_messages([user_input])
        ├── InferenceScope (inference_details, agent_details, tenant_details)
        │     ├── agent.ainvoke({messages}) — LangGraph execution
        │     ├── record_input_tokens / record_output_tokens
        │     ├── record_finish_reasons(["stop"])
        │     └── record_output_messages([reply])
        ├── ExecuteToolScope (per tool call)
        │     └── record_response(result)
        └── record_output_messages([reply])
```

Key data objects:

| Object | Fields |
|---|---|
| `AgentDetails` | `agent_id`, `agent_name`, `agent_description`, `tenant_id` |
| `TenantDetails` | `tenant_id` |
| `InvokeAgentDetails` | `details` (AgentDetails), `session_id` (correlation UUID) |
| `InferenceCallDetails` | `operationName` (CHAT), `model`, `providerName` |
| `A365Request` | `content` (user input), `execution_type` (HUMAN_TO_AGENT) |
| `ToolCallDetails` | `tool_name`, `arguments`, `tool_type` (FUNCTION) |

Token usage is extracted from the last AI message's `usage_metadata` when available (`input_tokens`/`prompt_tokens` and `output_tokens`/`completion_tokens`).

### Fallback Path

When A365 is not available (`_a365_available = False`), the `/api/chat` route falls back to `_run_chat_agent()` — the same LangGraph execution without any observability scopes.

### Environment Variables

Two environment variables are set by the Bicep deployment (when `enableA365Observability=true`):

| Variable | Purpose |
|---|---|
| `ENABLE_A365_OBSERVABILITY=true` | Enables scope-level span creation (required for traces to appear) |
| `ENABLE_A365_OBSERVABILITY_EXPORTER=true` | Routes spans to the Agent365 backend |

These are read internally by the A365 SDK. The Python code's outer guard (`if AGENTID_SIDECAR_URL and AGENT_IDENTITY_APP_ID`) controls whether `a365_configure()` is called at all.

Telemetry is exported to the Agent365 backend using a token acquired from the sidecar's `AgentToken` downstream API.

### Required Packages

```
microsoft-agents-a365-observability-core==0.1.0
microsoft-agents-a365-observability-extensions-langchain==0.1.0
```

These are included in the chat agent's `requirements.txt` and import conditionally at startup.

---

## Platform Observability

| Resource | Purpose |
|----------|---------|
| Log Analytics Workspace (`law-aigw-*`) | Central log store, 30-day retention |
| Application Insights (`appi-aigw-*`) | APIM request/response logging, traces |
| APIM Diagnostic Settings | Platform logs + metrics → Log Analytics |
| APIM API Diagnostics | Request/response logging → App Insights (100% sampling) |
| Container Apps Logs | Routed to Log Analytics via `appLogsConfiguration` |
| Foundry App Insights Connection | Connected to both hub and spoke Foundry projects |

APIM uses W3C trace correlation, so traces can be followed from browser → APIM → container app → APIM (second hop) → Foundry.

---

## Security Model

| Layer | Mechanism |
|-------|-----------|
| **Internet → APIM** | APIM is publicly accessible (External VNet mode). The `/openai/*` API requires a subscription key. The `/chat/*` API is open (frontend). |
| **APIM → Foundry** | Managed identity authentication. APIM's system-assigned identity has `Cognitive Services User` role on the AI Services account. No API keys stored. |
| **APIM → Container App** | Private networking. APIM is VNet-integrated, resolves the app's private IP via DNS, connects through VNet peering to the PE. The CAE has `publicNetworkAccess: Disabled`. |
| **Container App → APIM** | APIM subscription key (`spoke-subscription`) stored as a container app secret. Injected via `APIM_API_KEY` env var. |
| **Container App → Foundry** | `DefaultAzureCredential` (system-assigned managed identity). Azure AI Developer role on the spoke Foundry account. |
| **Container App → ACR** | System-assigned managed identity with `AcrPull` role. No admin credentials. |
| **Agent Identity → Resources** | (Optional) When Agent Identity is enabled, the Agent Identity SP has `Storage Blob Data Contributor` on spoke storage and `Cognitive Services User` on the Foundry account. Tokens are acquired via the auth sidecar — no credentials in app code. |
| **A365 Telemetry Export** | (Preview) Agent365 backend authentication via AgentToken acquired from the sidecar. |
| **Foundry → APIM** | APIM gateway connection with subscription key (for agent model inference). |
| **All hub PaaS services** | Private endpoints only. Storage, AI Search, Cosmos DB, AI Services all accessible only via PE. |
| **Spoke subnet** | NSG `Deny-Internet-Inbound` rule blocks all public internet ingress. |

---

## File Structure

```
├── infra/
│   ├── networking.bicep                # Phase 1 — hub + spoke VNets, peering, DNS
│   ├── hub.bicep                       # Phase 2 — observability, Foundry hub, APIM
│   ├── spoke.bicep                     # Phase 3 — Container Apps, optional spoke Foundry
│   ├── connectivity.bicep              # Phase 4 — Foundry PEs, APIM Chat API, DNS, RBAC
│   └── modules/
│       ├── peering.bicep               # Generic VNet peering helper
│       ├── dns-zone-link.bicep         # Generic DNS zone VNet link helper
│       ├── hub/
│       │   ├── networking.bicep        # Hub VNet, 3 subnets, NSGs
│       │   ├── dns.bicep               # 7 private DNS zones + hub VNet links
│       │   ├── observability.bicep     # Log Analytics + App Insights
│       │   ├── foundry-core.bicep      # AI Foundry account, project, caphosts, connections, RBAC
│       │   ├── foundry-network.bicep   # AI Foundry private endpoints (post-account)
│       │   ├── apim.bicep              # APIM instance + OpenAI API + policies
│       │   ├── apim-chat-api.bicep     # APIM API for /chat/* → spoke app
│       │   ├── cae-dns-wildcard.bicep  # Wildcard A record for CAE PE
│       │   └── policies/
│       │       └── openai-api-policy.xml
│       └── spoke/
│           ├── networking.bicep        # Spoke VNet, 2-3 subnets, NSGs
│           ├── container-apps.bicep    # ACR + CAE + container app + PE
│           ├── foundry-role.bicep      # Container App → Foundry RBAC
│           └── pe-nic-ip.bicep         # Helper to extract PE NIC IP
├── apps/
│   └── chat-agent/
│       ├── main.py                     # FastAPI app (direct + Foundry agent modes)
│       ├── static/index.html           # Chat UI (2-tab interface)
│       ├── Dockerfile                  # Python 3.12-slim + uvicorn, port 8000
│       └── requirements.txt            # fastapi, openai, azure-ai-projects, httpx
├── scripts/
│   ├── deploy.sh                    # Phased orchestrator (entry point)
│   ├── postprovision.sh             # Caphost creation + chat-agent build/deploy
│   ├── preprovision.sh              # Optional feature prompts
│   ├── setup_agent_identity.sh      # Entra Agent Identity setup (Blueprint, FIC, RBAC)
│   ├── deploy-chat-agent.sh         # Manual build + deploy (chat agent only)
│   └── test-gateway.sh              # Gateway test suite
├── architecture.drawio              # Editable architecture diagram
├── architecture.png                 # Architecture diagram image
├── architecture.md                  # ASCII traffic flows + resource summary
└── deepdive.md                      # This document
```

---

## Deployment Commands

```bash
# Full phased infrastructure deployment (networking → hub → spoke → connectivity → postprovision)
./scripts/deploy.sh

# The postprovision phase automatically:
#   1. Creates Foundry capability hosts (long-running REST polling)
#   2. Builds chat-agent image via ACR Tasks
#   3. Updates the Container App to the new image (port 8000)

# Manual: build and deploy the chat agent only (fast — skips infra)
./scripts/deploy-chat-agent.sh

# Test the gateway
./scripts/test-gateway.sh

# Test all three modes
curl -s https://<apim-url>/chat/health
curl -s -X POST https://<apim-url>/chat/api/chat \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello!"}]}'
curl -s -X POST https://<apim-url>/chat/api/agent/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello!","model":"gpt-4o"}'
curl -s -X POST https://<apim-url>/chat/api/hosted/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"What time is it?","model":"gpt-4o"}'
```

---

## Key Design Decisions

1. **APIM as the single entry point** — All model access goes through APIM, enabling centralized auth, rate limiting, logging, and multi-backend routing without exposing Foundry credentials to spoke teams.

2. **Managed identity over API keys** — APIM authenticates to Foundry using its system-assigned MI. Spokes authenticate to APIM with subscription keys. No Foundry API keys are ever distributed.

3. **Private Endpoints everywhere** — Every PaaS service (AI Services, Storage, Search, Cosmos, CAE) is accessed via private endpoints. The spoke CAE has `publicNetworkAccess: Disabled`.

4. **External VNet integration for APIM** — Keeps the public gateway URL working (needed for browser access to `/chat/`) while enabling private connectivity to spoke apps via the VNet.

5. **Wildcard DNS for CAE PE** — The PE DNS zone group only creates records for the environment prefix, not individual app FQDNs. A wildcard A record ensures all apps in the environment resolve to the PE private IP.

6. **ACR Tasks for builds** — Cloud-based Docker builds (`az acr build`) eliminate the need for local Docker. The postprovision hook handles both images automatically.

7. **Reusable Foundry module** — The same `foundry.bicep` module is used for both hub and spoke Foundry deployments, differentiated by `instanceSuffix`. The spoke Foundry adds APIM gateway + ACR connections and the account-level capability host.

8. **BYO Gateway with dynamic discovery** — The spoke Foundry's `apim-gateway` connection (category: `ApiManagement`) points to the hub APIM's `/openai` endpoint. Foundry dynamically discovers available models by querying APIM's deployment list endpoint — no static model list needed.

9. **Two-tier agent architecture** — Direct inference (OpenAI SDK) and prompt agents (`PromptAgentDefinition`) both route through the same APIM gateway, giving teams flexibility to choose the right abstraction level.

10. **Postprovision phase for CI** — Solves the chicken-and-egg problem (ACR must exist before image push) and handles the lifecycle: create capability hosts → build chat-agent image → deploy container app. Uses unique timestamp tags to avoid caching issues.

11. **Entra Agent Identity for per-agent security** — Each agent gets its own Entra identity (Blueprint + Agent Identity + FIC) with dedicated RBAC roles. Supports both autonomous agents (own security context) and on-behalf-of agents (Digital Colleague pattern with delegated permissions). The auth sidecar centralizes token exchange in a separate container — the app code has zero auth logic.

12. **A365 observability (preview)** — The Microsoft Agent 365 SDK traces LangChain/LangGraph executions end-to-end with explicit scopes (`InvokeAgentScope`, `InferenceScope`, `ExecuteToolScope`) and automatic chain instrumentation via `CustomLangChainInstrumentor`. Traces are exported to the Agent365 backend using Agent Identity tokens. If the packages aren't installed, the app falls back to `_run_chat_agent()` without observability — no hard dependency.
