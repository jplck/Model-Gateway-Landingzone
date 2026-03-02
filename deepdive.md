# AI Gateway Landing Zone — Architecture Deep Dive

## Overview

This repository implements a **hub-spoke AI Gateway Landing Zone** on Azure. The central idea is to place Azure API Management (APIM) in the hub as a **model gateway** that fronts Azure AI Foundry model endpoints, while spoke teams deploy their applications into isolated Container Apps environments and consume AI models exclusively through the gateway.

The entire infrastructure is defined in Bicep, deployed via Azure Developer CLI (`azd`), and follows a phased approach where each phase can be deployed incrementally.

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
│  │  │  │ Chat Agent (FastAPI+LangChain)│  │                │  │ │ │  │
│  │  │  │ external: true (within CAE)   │◄─┼────────────────┘  │ │ │  │
│  │  │  │ Calls APIM /openai server-side│  │                   │ │ │  │
│  │  │  └───────────────────────────────┘  │                   │ │ │  │
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
| 7b | `hub/apim-chat-api` | APIM API exposing `/chat/*` → spoke container app |
| 8 | `hub/foundry` (conditional) | Optional spoke Foundry for Agent Service |

---

## Network Architecture

### Hub VNet (`10.0.0.0/16`)

| Subnet | CIDR | Purpose | Notes |
|--------|------|---------|-------|
| `snet-apim` | `10.0.1.0/24` | APIM VNet integration | NSG allows 443 (HTTPS), 3443 (management), 6390 (LB) |
| `snet-pe` | `10.0.2.0/24` | Private endpoints | AI Services, Storage, Search, Cosmos DB |
| `snet-agent` | `10.0.3.0/24` | AI Foundry agent subnet | Delegated to `Microsoft.App/environments` |

### Spoke VNet (`10.1.0.0/16`)

| Subnet | CIDR | Purpose | Notes |
|--------|------|---------|-------|
| `snet-container-apps` | `10.1.0.0/23` | Container Apps Environment | Delegated to `Microsoft.App/environments`, /23 minimum |
| `snet-pe` | `10.1.2.0/24` | Private endpoints | CAE Private Endpoint (IP: `10.1.2.4`) |
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

APIM is deployed with `virtualNetworkType: 'External'`, which:
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

| Operation | Method | URL Template |
|-----------|--------|-------------|
| Chat Frontend | GET | `/chat/` |
| Health Check | GET | `/chat/health` |
| Chat API | POST | `/chat/api/chat` |

**No subscription required** — the chat frontend is publicly accessible through APIM. The chat agent authenticates to APIM's OpenAI API server-side using its own subscription key.

The APIM policy sets `backend-id="chat-app-backend"`, which points to `https://<container-app-fqdn>`. CORS is enabled for browser access.

### Product & Subscription

A `model-gateway` product groups the OpenAI API. A `spoke-subscription` provides the key that spoke apps use. This key is injected as a secret into the container app environment.

---

## AI Foundry (Capability Host Pattern)

The Foundry module (`hub/foundry.bicep`) deploys the full Azure AI Foundry stack:

```
AI Services Account (Microsoft.CognitiveServices/accounts, kind: AIServices)
  └── gpt-4o deployment (GlobalStandard, 10 TPM)

AI Foundry Hub (Microsoft.MachineLearningServices/workspaces, kind: Hub)
  └── AI Foundry Project (kind: Project)
       └── Capability Host
            ├── Storage connection
            ├── AI Search connection
            ├── Cosmos DB connection
            └── AI Services connection (+ optional APIM gateway connection)
```

**Supporting resources:**
- Storage Account (HierarchicalNamespace for ADLS Gen2)
- AI Search (Basic SKU)
- Cosmos DB (Serverless, NoSQL)

**Private endpoints** (4 total, all in `snet-pe`):
- AI Services → `privatelink.cognitiveservices.azure.com` + `privatelink.openai.azure.com`
- Storage → `privatelink.blob.core.windows.net`
- AI Search → `privatelink.search.windows.net`
- Cosmos DB → `privatelink.documents.azure.com`

**RBAC assignments:**
- Foundry hub identity → Cognitive Services OpenAI Contributor on AI Services
- Foundry hub identity → Search Index Data Contributor + Search Service Contributor on AI Search
- Foundry hub identity → Storage Blob Data Contributor on Storage

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
| Image | `acraigw....azurecr.io/chat-agent:latest` (built via ACR Tasks) |
| Port | 8000 |
| CPU / Memory | 0.5 vCPU / 1 GiB |
| Min / Max replicas | 1 / 3 |
| Ingress | `external: true` (within CAE), via APIM only |
| Identity | SystemAssigned (used for ACR Pull) |

**Environment variables:**
- `APIM_GATEWAY_URL` — hub APIM URL
- `APIM_API_KEY` — subscription key (from secret `apim-api-key`)
- `OPENAI_DEPLOYMENT_NAME` — `gpt-4o`

### Azure Container Registry

ACR Basic SKU with admin disabled. The container app's system-assigned managed identity has `AcrPull` role. Images are built via **ACR Tasks** (cloud build) — no local Docker required:

```bash
az acr build --registry <acr-name> --image chat-agent:latest ./apps/chat-agent
```

---

## Chat Agent Application

### Architecture

```
Browser
  → APIM /chat/           (GET: HTML frontend)
  → APIM /chat/api/chat   (POST: chat message)
      → Container App /api/chat
          → LangChain AzureChatOpenAI
              → APIM /openai/deployments/gpt-4o/chat/completions
                  → Azure AI Foundry (gpt-4o)
```

The app is a **FastAPI** server with three routes:

| Route | Purpose |
|-------|---------|
| `GET /` | Serves the static HTML chat UI |
| `POST /api/chat` | Receives chat messages, invokes LangChain, returns AI response |
| `GET /health` | Returns health status including LLM configuration state |

### LangChain Integration

The app uses `langchain-openai`'s `AzureChatOpenAI` class configured to point at the APIM gateway (not directly at Foundry):

```python
llm = AzureChatOpenAI(
    azure_endpoint=APIM_GATEWAY_URL,     # https://apim-xxx.azure-api.net
    api_key=APIM_API_KEY,                 # APIM subscription key
    azure_deployment="gpt-4o",
    api_version="2024-10-21",
)
```

This means the chat agent authenticates to APIM with a subscription key, and APIM authenticates to Foundry with managed identity. The app never has direct access to Foundry credentials.

### Chat UI

The HTML frontend (`static/index.html`) provides:
- Multi-turn conversation with message history
- System message configuration
- Auto-resizing textarea
- Visual display of the request flow

---

## Request Flow (End-to-End)

### 1. User opens chat UI

```
Browser  →  APIM (public IP)  →  /chat/
         →  APIM resolves chat-app-backend FQDN via private DNS  →  10.1.2.4
         →  PE in spoke snet-pe  →  CAE  →  Container App GET /
         →  Returns index.html
```

### 2. User sends a chat message

```
Browser  →  POST APIM/chat/api/chat  {messages: [...]}
         →  APIM (no subscription required)  →  Container App POST /api/chat

Container App  →  LangChain AzureChatOpenAI
               →  POST APIM/openai/deployments/gpt-4o/chat/completions
                   Header: api-key: <spoke-subscription-key>
               →  APIM validates subscription key
               →  APIM policy: acquires MI token for cognitiveservices.azure.com
               →  APIM policy: sets Authorization: Bearer <MI-token>
               →  APIM policy: rate-limit check (100/min)
               →  Forward to foundry-backend (AI Services endpoint)

AI Foundry  →  gpt-4o processes request  →  returns completion

Reverse path through APIM  →  Container App  →  APIM /chat  →  Browser
```

### 3. DNS resolution (APIM → spoke container app)

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

## Observability

| Resource | Purpose |
|----------|---------|
| Log Analytics Workspace (`law-aigw-*`) | Central log store, 30-day retention |
| Application Insights (`appi-aigw-*`) | APIM request/response logging, traces |
| APIM Diagnostic Settings | Platform logs + metrics → Log Analytics |
| APIM API Diagnostics | Request/response logging → App Insights (100% sampling) |
| Container Apps Logs | Routed to Log Analytics via `appLogsConfiguration` |

APIM uses W3C trace correlation, so traces can be followed from browser → APIM → container app → APIM (second hop) → Foundry.

---

## Security Model

| Layer | Mechanism |
|-------|-----------|
| **Internet → APIM** | APIM is publicly accessible (External VNet mode). The `/openai/*` API requires a subscription key. The `/chat/*` API is open (frontend). |
| **APIM → Foundry** | Managed identity authentication. APIM's system-assigned identity has `Cognitive Services User` role on the AI Services account. No API keys stored. |
| **APIM → Container App** | Private networking. APIM is VNet-integrated, resolves the app's private IP via DNS, connects through VNet peering to the PE. The CAE has `publicNetworkAccess: Disabled`. |
| **Container App → APIM** | APIM subscription key (`spoke-subscription`) stored as a container app secret. Injected via `APIM_API_KEY` env var. |
| **Container App → ACR** | System-assigned managed identity with `AcrPull` role. No admin credentials. |
| **All hub PaaS services** | Private endpoints only. Storage, AI Search, Cosmos DB, AI Services all accessible only via PE. |
| **Spoke subnet** | NSG `Deny-Internet-Inbound` rule blocks all public internet ingress. |

---

## File Structure

```
├── azure.yaml                          # azd project config
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
│       │   ├── apim-chat-api.bicep     # APIM API for /chat/* → spoke app
│       │   ├── cae-dns-wildcard.bicep  # Wildcard A record for CAE PE
│       │   └── policies/
│       │       └── openai-api-policy.xml  # APIM inbound policy (MI auth, rate limit)
│       └── spoke/
│           ├── networking.bicep        # Spoke VNet, 2-3 subnets, NSGs
│           └── container-apps.bicep    # ACR + CAE + container app + PE
├── apps/
│   └── chat-agent/
│       ├── main.py                     # FastAPI + LangChain app
│       ├── static/index.html           # Chat UI
│       ├── Dockerfile                  # Python 3.12-slim + uvicorn
│       └── requirements.txt            # Dependencies
└── scripts/
    ├── deploy-chat-agent.sh            # Build + deploy script (ACR Tasks + az containerapp update)
    └── test-gateway.sh                 # Comprehensive gateway test suite
```

---

## Deployment Commands

```bash
# Full infrastructure deployment
azd up

# Infrastructure only (no app deploy)
azd provision --no-prompt

# Build and deploy the chat agent (fast — no full provision)
./scripts/deploy-chat-agent.sh

# Test the gateway
./scripts/test-gateway.sh
```

---

## Key Design Decisions

1. **APIM as the single entry point** — All model access goes through APIM, enabling centralized auth, rate limiting, logging, and multi-backend routing without exposing Foundry credentials to spoke teams.

2. **Managed identity over API keys** — APIM authenticates to Foundry using its system-assigned MI. Spokes authenticate to APIM with subscription keys. No Foundry API keys are ever distributed.

3. **Private Endpoints everywhere** — Every PaaS service (AI Services, Storage, Search, Cosmos, CAE) is accessed via private endpoints. The spoke CAE has `publicNetworkAccess: Disabled`.

4. **External VNet integration for APIM** — Keeps the public gateway URL working (needed for browser access to `/chat/`) while enabling private connectivity to spoke apps via the VNet.

5. **Wildcard DNS for CAE PE** — The PE DNS zone group only creates records for the environment prefix, not individual app FQDNs. A wildcard A record ensures all apps in the environment resolve to the PE private IP.

6. **ACR Tasks for builds** — Cloud-based Docker builds (`az acr build`) eliminate the need for local Docker. The deploy script uses `az containerapp update` for fast revisions instead of full `azd provision` cycles.

7. **Reusable Foundry module** — The same `foundry.bicep` module is used for both hub and spoke Foundry deployments, differentiated by `instanceSuffix`. The spoke Foundry is optional (`deploySpokeFoundry` flag).
