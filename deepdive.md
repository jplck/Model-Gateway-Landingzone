# AI Gateway Landing Zone — Architecture Deep Dive

## Overview

This repository implements a **hub-spoke AI Gateway Landing Zone** on Azure. The central idea is to place Azure API Management (APIM) in the hub as a **model gateway** that fronts Azure AI Foundry model endpoints, while spoke teams deploy their applications into isolated Container Apps environments and consume AI models exclusively through the gateway.

The entire infrastructure is defined in Bicep, deployed via Azure Developer CLI (`azd`), and follows a phased approach where each phase can be deployed incrementally.

The chat agent application offers **three modes** of AI interaction:

1. **Direct Inference** — OpenAI SDK → APIM → Hub Foundry (API key auth)
2. **Foundry Agent** — PromptAgent SDK → Agent Service → APIM Gateway → Hub Foundry
3. **Hosted Agent** — ImageBasedHostedAgent (LangGraph container) → APIM Gateway → Hub Foundry

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
│  │  │  │ Chat Agent (FastAPI+OpenAI)   │  │                │  │ │ │  │
│  │  │  │ 3 modes: Direct/Agent/Hosted  │◄─┼────────────────┘  │ │ │  │
│  │  │  │ Calls APIM /openai server-side│  │                   │ │ │  │
│  │  │  └───────────────────────────────┘  │                   │ │ │  │
│  │  └─────────────────────────────────────┘                   │ │ │  │
│  │                                                             │ │ │  │
│  │  ┌─────────────────────────────────────┐                   │ │ │  │
│  │  │ Spoke AI Foundry (Agent Service)    │                   │ │ │  │
│  │  │  • apim-gateway → APIM /openai      │                   │ │ │  │
│  │  │  • acr-connection → spoke ACR        │                   │ │ │  │
│  │  │  • Account + project cap hosts       │                   │ │ │  │
│  │  │  • Hosted agent: gw-hosted-agent     │                   │ │ │  │
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

The `main.bicep` orchestrator is organized into numbered phases. Each can be deployed incrementally by commenting out later phases.

| Phase | Module | Purpose |
|-------|--------|---------|
| 2 | `hub/networking`, `hub/dns`, `hub/observability` | Hub VNet, subnets, NSGs, 7 private DNS zones, Log Analytics, App Insights |
| 3 | `hub/foundry` | AI Foundry account + project + capability host + model deployments + private endpoints |
| 4 | `hub/apim` | API Management with OpenAI API, managed identity auth, rate limiting, spoke subscription |
| 5 | *(placeholder)* | Multi-backend load balancing — add more Foundry instances |
| 6 | `spoke/networking`, `peering` x2, `dns-zone-link` x7 | Spoke VNet, bidirectional peering, DNS zone links |
| 7 | `spoke/container-apps`, `cae-dns-wildcard` | ACR, Container Apps Environment, chat agent app, CAE private endpoint + wildcard DNS |
| 7b | `hub/apim-chat-api` | APIM API exposing `/chat/*` → spoke container app (7 operations) |
| 8 | `hub/foundry` (conditional) | Spoke Foundry for Agent Service — with APIM gateway connection, ACR connection, account-level capability host (`enableHostedAgents: true`) |
| 8b | `spoke/foundry-role` | Container App → Spoke Foundry RBAC (Azure AI Developer role) |
| 8c | `spoke/acr-pull-role` | Foundry Project → ACR AcrPull RBAC (hosted agent image pull) |

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
| Chat Completions | POST | `/openai/deployments/{deployment-id}/chat/completions` |
| Completions | POST | `/openai/deployments/{deployment-id}/completions` |
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
| Hosted Agent Chat | POST | `/api/hosted/chat` | Hosted Agent (LangGraph image) |
| Static Assets | GET | `/static/*` | CSS/JS assets for the UI |

**No subscription required** — the chat frontend is publicly accessible through APIM. The chat agent authenticates to APIM's OpenAI API server-side using its own subscription key.

The APIM policy sets `backend-id="chat-app-backend"`, which points to `https://<container-app-fqdn>`. CORS is enabled for browser access.

### Product & Subscription

A `model-gateway` product groups the OpenAI API. A `spoke-subscription` provides the key that spoke apps use. This key is injected as a secret into the container app environment.

---

## AI Foundry (Capability Host Pattern)

The Foundry module (`hub/foundry.bicep`) is **reusable** for both hub and spoke deployments via the `instanceSuffix` parameter. It deploys the full Azure AI Foundry stack:

```
AI Services Account (Microsoft.CognitiveServices/accounts, kind: AIServices)
  ├── gpt-4o deployment (hub only — spoke uses hub models via APIM)
  ├── Account-level Capability Host (conditional — enableHostedAgents)
  │     └── capabilityHostKind: 'Agents', enablePublicHostingEnvironment: true
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
       │     ├── App Insights (AppInsights, ApiKey auth) — conditional
       │     └── ACR (ContainerRegistry, ManagedIdentity) — spoke only
       └── RBAC assignments (6 total — project + account identities → backing resources)
```

### Two Capability Host Levels

1. **Account-level** (`Microsoft.CognitiveServices/accounts/capabilityHosts@2025-10-01-preview`) — Only deployed when `enableHostedAgents: true` (spoke Foundry). Sets `enablePublicHostingEnvironment: true` to enable Foundry to pull and run container images as hosted agents.

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

2. **ACR Connection** (`category: ContainerRegistry`) — registered on the **project**. Points to the spoke ACR. Uses managed identity auth. Required for the Foundry project to pull hosted agent container images.

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

The chat agent (`apps/chat-agent`) is a **FastAPI** server (v3.0.0) with three AI interaction modes and six routes:

| Route | Method | Purpose | SDK |
|-------|--------|---------|-----|
| `/` | GET | Chat UI (static HTML with 3-tab interface) | — |
| `/health` | GET | Health check + configuration status | — |
| `/api/models` | GET | Dynamic model discovery via APIM gateway | httpx |
| `/api/chat` | POST | Direct inference | OpenAI SDK (`AzureOpenAI`) |
| `/api/agent/chat` | POST | Foundry Agent (PromptAgent) | azure-ai-projects (`AIProjectClient`) |
| `/api/hosted/chat` | POST | Hosted Agent (LangGraph container) | azure-ai-projects (`AIProjectClient`) |

### Mode 1: Direct Inference (`/api/chat`)

Uses the **OpenAI SDK** (`AzureOpenAI`) configured with the APIM gateway URL and subscription key:

```python
oai_direct = AzureOpenAI(
    azure_endpoint=APIM_GATEWAY_URL,     # https://apim-xxx.azure-api.net
    api_key=APIM_API_KEY,                 # APIM subscription key
    api_version="2024-10-21",
)
response = oai_direct.chat.completions.create(model="gpt-4o", messages=messages)
```

The app authenticates to APIM with a subscription key, and APIM authenticates to Foundry with managed identity. The app never has direct access to Foundry credentials.

### Mode 2: Foundry Agent (`/api/agent/chat`)

Uses the **Azure AI Projects SDK** (`AIProjectClient` + `PromptAgentDefinition`) to create prompt-based agents via the Foundry Agent Service:

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

### Mode 3: Hosted Agent (`/api/hosted/chat`)

References a **pre-registered hosted agent** (`gw-hosted-agent`) — a LangGraph container running inside Foundry Agent Service:

```python
conv = oai.responses.create(
    model=model_ref,
    input=req.message,
    extra_body={"agent_reference": {"name": "gw-hosted-agent", "type": "agent_reference"}},
)
```

The hosted agent is a separate container image registered via `ImageBasedHostedAgentDefinition`. The chat agent invokes it the same way as a prompt agent — via the Responses API with `agent_reference`.

### Chat UI

The HTML frontend (`static/index.html`) provides:
- **Three-tab interface**: Direct Inference, Foundry Agent, Hosted Agent
- **Model selector** (agent/hosted tabs): Dynamic discovery via `/api/models`
- Multi-turn conversation with per-tab state
- Auto-resizing textarea
- Visual display of the current request flow path

---

## Hosted Agent (LangGraph Container)

The hosted agent (`apps/hosted-agent/`) is a **LangGraph** agent packaged as a container image that runs inside Foundry Agent Service.

### Agent Architecture

```
LLM (gpt-4o via APIM gateway)
  ↕
ReAct Loop (LangGraph StateGraph)
  ├── llm_call node — LLM decides to call a tool or respond
  ├── tool_node — Executes tool calls
  └── should_continue — Routes to tools or end
```

**Framework stack:**
- LangChain (`init_chat_model` with `azure_openai:gpt-4o`)
- LangGraph (`StateGraph` with `MessagesState`)
- `azure-ai-agentserver[langgraph]` (`from_langgraph` adapter — exposes Responses API v2)

**Three mock tools:**
- `get_current_time()` — returns current UTC time
- `roll_dice(sides=6)` — random dice roll
- `calculate(expression)` — evaluates safe math expressions

**Authentication:** Uses `DefaultAzureCredential` + `get_bearer_token_provider` for `cognitiveservices.azure.com/.default`. No API keys — the container's managed identity authenticates to the APIM gateway.

### Registration

The hosted agent is registered with Foundry via `scripts/deploy_hosted_agent.py`:

```python
agent = client.agents.create_version(
    agent_name="gw-hosted-agent",
    definition=ImageBasedHostedAgentDefinition(
        container_protocol_versions=[ProtocolVersionRecord(
            protocol=AgentProtocol.RESPONSES, version="v2")],
        cpu="1",
        memory="2Gi",
        image=image_tag,
        environment_variables={
            "AZURE_AI_PROJECT_ENDPOINT": project_endpoint,
            "AZURE_AI_MODEL_DEPLOYMENT_NAME": "gpt-4o",
            "AZURE_OPENAI_ENDPOINT": f"{apim_url}/openai",
            "OPENAI_API_VERSION": "2024-10-21",
        },
    ),
)
```

**Prerequisites for hosted agents in infrastructure:**
1. Account-level capability host with `enablePublicHostingEnvironment: true`
2. ACR connection on the Foundry project (`category: ContainerRegistry`, `authType: ManagedIdentity`)
3. AcrPull RBAC for the Foundry project identity on the ACR
4. APIM gateway connection for model access

---

## Request Flows

### Flow 1: Direct Inference (POST /api/chat)

```
Browser  →  POST APIM/chat/api/chat  {messages: [...]}
         →  APIM (no subscription required)  →  Container App POST /api/chat

Container App  →  OpenAI SDK (AzureOpenAI)
               →  POST APIM/openai/deployments/gpt-4o/chat/completions
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

### Flow 3: Hosted Agent (POST /api/hosted/chat)

```
Browser  →  POST APIM/chat/api/hosted/chat  {message, model, thread_id}
         →  Container App POST /api/hosted/chat

Container App  →  oai.responses.create(model, input, agent_reference="gw-hosted-agent")
               →  Spoke Foundry Agent Service
                    └── Pulls & runs hosted-agent container from ACR
                         └── LangGraph agent (tool loop)
                              └── LLM calls via APIM gateway → Hub AI Services
                              └── Tool calls (get_current_time, roll_dice, calculate)

Reverse path: Hosted Agent → Spoke Agent Service → Container App → APIM /chat → Browser
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

The `postprovision.sh` hook runs automatically after `azd provision` and handles two image builds plus hosted agent registration:

```
azd provision
  └── Bicep deploys all infra
       └── postprovision.sh
            ├── 1. Build chat-agent image
            │     └── az acr build → chat-agent:v{timestamp}
            │     └── az containerapp update → deploy to spoke
            │     └── az containerapp ingress update → port 8000
            │     └── azd env set CHAT_AGENT_IMAGE
            │
            ├── 2. Build hosted-agent image
            │     └── az acr build → hosted-agent:v{timestamp}
            │     └── azd env set HOSTED_AGENT_IMAGE
            │
            └── 3. Register hosted agent (if spoke Foundry exists)
                  └── python3 deploy_hosted_agent.py
                       └── ImageBasedHostedAgentDefinition
                       └── agent_name: gw-hosted-agent
```

---

## Observability

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
| **Foundry → ACR** | Project-level managed identity with `AcrPull` role (for hosted agent image pull). |
| **Foundry → APIM** | APIM gateway connection with subscription key (for agent model inference). |
| **All hub PaaS services** | Private endpoints only. Storage, AI Search, Cosmos DB, AI Services all accessible only via PE. |
| **Spoke subnet** | NSG `Deny-Internet-Inbound` rule blocks all public internet ingress. |

---

## File Structure

```
├── azure.yaml                          # azd project config (postprovision hook)
├── infra/
│   ├── main.bicep                      # Subscription-scoped orchestrator
│   ├── main.bicepparam                 # Parameters (env var bindings)
│   └── modules/
│       ├── peering.bicep               # Generic VNet peering helper
│       ├── dns-zone-link.bicep         # Generic DNS zone VNet link helper
│       ├── hub/
│       │   ├── networking.bicep        # Hub VNet, 3 subnets, NSGs
│       │   ├── dns.bicep               # 7 private DNS zones + hub VNet links
│       │   ├── observability.bicep     # Log Analytics + App Insights
│       │   ├── foundry.bicep           # AI Foundry full stack (reusable hub/spoke)
│       │   ├── apim.bicep              # APIM instance + OpenAI API + policies
│       │   ├── apim-chat-api.bicep     # APIM API for /chat/* → spoke app (7 ops)
│       │   ├── cae-dns-wildcard.bicep  # Wildcard A record for CAE PE
│       │   └── policies/
│       │       └── openai-api-policy.xml
│       └── spoke/
│           ├── networking.bicep        # Spoke VNet, 2-3 subnets, NSGs
│           ├── container-apps.bicep    # ACR + CAE + container app + PE
│           ├── foundry-role.bicep      # Container App → Foundry RBAC
│           ├── acr-pull-role.bicep     # Foundry Project → ACR AcrPull
│           └── pe-nic-ip.bicep         # Helper to extract PE NIC IP
├── apps/
│   ├── chat-agent/
│   │   ├── main.py                     # FastAPI app (3 modes: direct/agent/hosted)
│   │   ├── static/index.html           # Chat UI (3-tab interface)
│   │   ├── Dockerfile                  # Python 3.12-slim + uvicorn, port 8000
│   │   └── requirements.txt            # fastapi, openai, azure-ai-projects, httpx
│   └── hosted-agent/
│       ├── agent.py                    # LangGraph agent with tools
│       ├── Dockerfile                  # Python 3.12-slim, port 8088
│       └── requirements.txt            # langchain, langgraph, azure-ai-agentserver
├── scripts/
│   ├── postprovision.sh                # Build + deploy hook (2 images + agent registration)
│   ├── deploy_hosted_agent.py          # Register hosted agent with Foundry
│   ├── deploy-chat-agent.sh            # Manual build + deploy (chat agent only)
│   └── test-gateway.sh                 # Gateway test suite
├── architecture.drawio                 # Editable architecture diagram
├── architecture.png                    # Architecture diagram image
├── architecture.md                     # ASCII traffic flows + resource summary
└── deepdive.md                         # This document
```

---

## Deployment Commands

```bash
# Full infrastructure deployment
azd up

# Infrastructure only (no app deploy)
azd provision --no-prompt

# The postprovision hook automatically:
#   1. Builds chat-agent + hosted-agent images via ACR Tasks
#   2. Deploys chat-agent to Container App
#   3. Registers hosted agent with Foundry (if spoke Foundry exists)

# Manual: build and deploy the chat agent only (fast — no full provision)
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

9. **Three-tier agent architecture** — Direct inference (OpenAI SDK), prompt agents (PromptAgentDefinition), and hosted agents (ImageBasedHostedAgentDefinition) all route through the same APIM gateway, giving teams flexibility to choose the right abstraction level.

10. **Postprovision hook for CI** — Solves the chicken-and-egg problem (ACR must exist before image push) and handles the full lifecycle: build images → deploy container app → register hosted agent. Uses unique timestamp tags to avoid caching issues.
