# AI Gateway Landing Zone — Architecture

```
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │  Azure Subscription                                                                     │
 │                                                                                         │
 │  ┌───────────────────────────────────────────┐  ┌───────────────────────────────────────┐│
 │  │  Hub Resource Group                       │  │  Spoke Resource Group                 ││
 │  │                                           │  │                                       ││
 │  │  ┌──────────────────────────────────────┐  │  │  ┌──────────────────────────────────┐ ││
 │  │  │  Hub VNet  10.0.0.0/16              │  │  │  │  Spoke VNet  10.1.0.0/16         │ ││
 │  │  │                                      │  │  │  │                                  │ ││
 │  │  │  ┌────────────────────────────────┐  │  │  │  │  ┌────────────────────────────┐  │ ││
 │  │  │  │ snet-apim  10.0.1.0/24        │  │◄─┼──┼──┼──┤ snet-container-apps        │  │ ││
 │  │  │  │ (delegated: Web/serverFarms)  │  │  │  │  │  │  10.1.1.0/24               │  │ ││
 │  │  │  │                                │  │  │  │  │  │                            │  │ ││
 │  │  │  │  ┌──────────────────────────┐  │  │  │  │  │  │  ┌──────────────────────┐  │  │ ││
 │  │  │  │  │  APIM  (StandardV2)     │  │  │  │  │  │  │  │ Container Apps Env  │  │  │ ││
 │  │  │  │  │  ──────────────────     │  │  │  │  │  │  │  │ (Consumption)       │  │  │ ││
 │  │  │  │  │  VNet Integration       │  │  │  │  │  │  │  │ publicNetworkAccess │  │  │ ││
 │  │  │  │  │  (outbound only)        │  │  │  │  │  │  │  │ = Disabled          │  │  │ ││
 │  │  │  │  │                          │  │  │  │  │  │  │  │                      │  │  │ ││
 │  │  │  │  │  APIs:                   │  │  │  │  │  │  │  │  ┌────────────────┐  │  │  │ ││
 │  │  │  │  │  • /openai/* ──────────┐│  │  │  │  │  │  │  │  │  Chat Agent   │  │  │  │ ││
 │  │  │  │  │    (model gateway)     ││  │  │  │  │  │  │  │  │  (FastAPI)    │  │  │  │ ││
 │  │  │  │  │                        ││  │  │  │  │  │  │  │  │  Port 8000    │  │  │  │ ││
 │  │  │  │  │  • /chat/* ───────────┐││  │  │  │  │  │  │  │  │              │  │  │  │ ││
 │  │  │  │  │    (chat frontend)    │││  │  │  │  │  │  │  │  │ GET /models  │  │  │  │ ││
 │  │  │  │  │                       │││  │  │  │  │  │  │  │  │ POST /chat   │  │  │  │ ││
 │  │  │  │  └───────────────────────┼┼┘  │  │  │  │  │  │  │  │ POST /agent  │  │  │  │ ││
 │  │  │  │                          ││   │  │  │  │  │  │  │  │   /chat      │  │  │  │ ││
 │  │  │  └──────────────────────────┼┼───┘  │  │  │  └──┼──┼──┘              │  │  │  │ ││
 │  │  │                             ││      │  │  │     │  │  └────────────────┘  │  │  │ ││
 │  │  │  ┌────────────────────────┐ ││      │  │  │     │  │                      │  │  │ ││
 │  │  │  │ snet-pe  10.0.2.0/24  │ ││      │  │  │  ┌──┼──┼──────────────────┐   │  │  │ ││
 │  │  │  │                        │◄┘│      │  │  │  │  │  │ Private Endpoint │   │  │  │ ││
 │  │  │  │  ┌──────────────────┐  │  │      │  │  │  │  │  │ (CAE wildcard)   │   │  │  │ ││
 │  │  │  │  │ Private Endpoints│  │  │      │  │  │  │  │  └──────────────────┘   │  │  │ ││
 │  │  │  │  │  • AI Services   │  │  │      │  │  │  │  │                         │  │  │ ││
 │  │  │  │  │  • Storage       │  │  │      │  │  │  └──┼─────────────────────────┘  │  │ ││
 │  │  │  │  │  • Search        │  │  │      │  │  │     │                             │  │ ││
 │  │  │  │  │  • Cosmos DB     │  │  │      │  │  │  ┌──┼─────────────────────────┐   │  │ ││
 │  │  │  │  └──────────────────┘  │  │      │  │  │  │  │ snet-pe  10.1.2.0/24   │   │  │ ││
 │  │  │  └────────────────────────┘  │      │  │  │  │  │                         │   │  │ ││
 │  │  │                              │      │  │  │  │  │  ┌───────────────────┐   │   │  │ ││
 │  │  │  ┌────────────────────────┐  │      │  │  │  │  │  │ Private Endpoints│   │   │  │ ││
 │  │  │  │ snet-agent 10.0.3.0/24│  │      │  │  │  │  │  │ • AI Services    │   │   │  │ ││
 │  │  │  │ (Foundry Agent svc)   │  │      │  │  │  │  │  │ • Storage        │   │   │  │ ││
 │  │  │  └────────────────────────┘  │      │  │  │  │  │  │ • Search         │   │   │  │ ││
 │  │  │                              │◄─────┼──┼──┼──┤  │  │ • Cosmos DB      │   │   │  │ ││
 │  │  └──────────────────────────────┘      │  │  │  │  │  │ • ACR            │   │   │  │ ││
 │  │         VNet Peering (bidirectional)   │  │  │  │  │  └───────────────────┘   │   │  │ ││
 │  │  ──────────────────────────────────────┼──┼──┤  │  └─────────────────────────┘   │  │ ││
 │  │                                        │  │  │  │                                │  │ ││
 │  │                                        │  │  │  │  ┌─────────────────────────┐   │  │ ││
 │  │                                        │  │  │  │  │ snet-agent 10.1.3.0/24 │   │  │ ││
 │  │                                        │  │  │  │  │ (Foundry Agent svc)     │   │  │ ││
 │  │                                        │  │  │  │  └─────────────────────────┘   │  │ ││
 │  │                                        │  │  │  │                                │  │ ││
 │  │                                        │  │  └──┼────────────────────────────────┘  │ ││
 │  │                                        │  │     └───────────────────────────────────┘ ││
 │  │                                        │  │                                           ││
 │  │  ┌──────────────────────────────────┐  │  │  ┌───────────────────────────────────────┐││
 │  │  │  Hub AI Foundry                  │  │  │  │  Spoke AI Foundry                     │││
 │  │  │                                  │  │  │  │                                       │││
 │  │  │  AI Services Account             │  │  │  │  AI Services Account                  │││
 │  │  │    └─ gpt-4o deployment          │  │  │  │    └─ (no model deployments)          │││
 │  │  │                                  │  │  │  │                                       │││
 │  │  │  Foundry Project                 │  │  │  │  Foundry Project                      │││
 │  │  │    └─ Capability Host            │  │  │  │    └─ Capability Host                 │││
 │  │  │                                  │  │  │  │                                       │││
 │  │  │  Backing Resources:              │  │  │  │  Connections:                         │││
 │  │  │    • Storage Account             │  │  │  │    • storage, search, cosmos           │││
 │  │  │    • AI Search                   │  │  │  │    • App Insights                     │││
 │  │  │    • Cosmos DB (data-plane RBAC) │  │  │  │    • ┌─────────────────────────────┐  │││
 │  │  │                                  │  │  │  │    │ │ apim-gateway (ApiMgmt)      │  │││
 │  │  │  Connections:                    │  │  │  │    │ │ → APIM /openai endpoint     │  │││
 │  │  │    • storage, search, cosmos     │  │  │  │    │ │ Dynamic model discovery     │  │││
 │  │  │    • App Insights                │  │  │  │    │ └─────────────────────────────┘  │││
 │  │  │                                  │  │  │  │    │                                   │││
 │  │  └──────────────────────────────────┘  │  │  └────┼───────────────────────────────────┘││
 │  │                                        │  │       │                                    ││
 │  │  ┌──────────────────────────────────┐  │  │  ┌────┼──────────────────────────────┐    ││
 │  │  │  Observability                   │  │  │  │    │  ACR (Azure Container Reg)   │    ││
 │  │  │    • Log Analytics Workspace     │  │  │  │    │  └─ chat-agent:v{timestamp}  │    ││
 │  │  │    • Application Insights        │  │  │  └────┼──────────────────────────────┘    ││
 │  │  └──────────────────────────────────┘  │  │       │                                    ││
 │  │                                        │  │       │                                    ││
 │  │  ┌──────────────────────────────────┐  │  │       │                                    ││
 │  │  │  Private DNS Zones (hub-hosted)  │  │  │       │                                    ││
 │  │  │    • cognitiveservices            │  │  │       │                                    ││
 │  │  │    • openai                       │  │  │       │                                    ││
 │  │  │    • ai services                  │  │  │       │                                    ││
 │  │  │    • blob storage                 │  │  │       │                                    ││
 │  │  │    • search                       │  │  │       │                                    ││
 │  │  │    • cosmos db                    │  │  │       │                                    ││
 │  │  │    • container apps               │  │  │       │                                    ││
 │  │  │  (linked to both hub & spoke)     │  │  │       │                                    ││
 │  │  └──────────────────────────────────┘  │  │       │                                    ││
 │  │                                        │  │       │                                    ││
 │  └────────────────────────────────────────┘  └───────┼────────────────────────────────────┘│
 │                                                      │                                     │
 └──────────────────────────────────────────────────────┼─────────────────────────────────────┘
                                                        │
                                                        │
      ═══════════════════════════════════════════════════╪═════════════════════════════════
                            TRAFFIC  FLOWS              │
      ═══════════════════════════════════════════════════╪═════════════════════════════════
                                                        │
                                                        │
   ┌──────────────────────────────────────────────────────────────────────────────────────┐
   │                                                                                      │
   │  Flow 1: Direct Inference (POST /chat)                                               │
   │  ─────────────────────────────────────                                               │
   │                                                                                      │
   │  User ──► APIM /chat/* ──► (VNet) ──► Spoke CAE (PE) ──► Chat Agent /api/chat        │
   │                                          │                                           │
   │                                          └──► OpenAI SDK ──► APIM /openai/*          │
   │                                                                │                     │
   │                                                                └──► Hub AI Services  │
   │                                                                     (gpt-4o)         │
   │                                                                                      │
   │  Flow 2: Agent Chat (POST /agent/chat)                                               │
   │  ────────────────────────────────────                                                 │
   │                                                                                      │
   │  User ──► APIM /chat/* ──► (VNet) ──► Spoke CAE (PE) ──► Chat Agent /api/agent/chat  │
   │                                          │                                           │
   │                                          └──► PromptAgent SDK ──► Spoke Foundry      │
   │                                                     │              (Agent Service)    │
   │                                                     │                   │             │
   │                                                     │                   ▼             │
   │                                                     │          apim-gateway conn      │
   │                                                     │                   │             │
   │                                                     │                   ▼             │
   │                                                     │            APIM /openai/*       │
   │                                                     │                   │             │
   │                                                     │                   ▼             │
   │                                                     │          Hub AI Services        │
   │                                                     │               (gpt-4o)          │
   │                                                     │                                 │
   │                                                     └──► Response with agent_reference│
   │                                                          uses responses.create()      │
   │                                                                                      │
   │  Flow 3: Model Discovery (GET /models)                                               │
   │  ────────────────────────────────────                                                 │
   │                                                                                      │
   │  User ──► APIM /chat/* ──► (VNet) ──► Spoke CAE (PE) ──► Chat Agent /api/models      │
   │                                          │                                           │
   │                                          └──► httpx ──► APIM /openai/deployments     │
   │                                                              │                       │
   │                                                              └──► ARM API (dynamic   │
   │                                                                   model discovery)   │
   │                                                                                      │
   └──────────────────────────────────────────────────────────────────────────────────────┘


      ═══════════════════════════════════════════════════════════════════════════════════
                            CI / CD  (postprovision phase)
      ═══════════════════════════════════════════════════════════════════════════════════

      ./scripts/deploy.sh ──► Bicep phases 1–4 ──► postprovision.sh (phase 5)
                                                      │
                                                      ├─ az acr build (cloud build)
                                                      │   └─ chat-agent:{timestamp}
                                                      │
                                                      ├─ az containerapp update
                                                      │   └─ sets new image + port 8000
                                                      │
                                                      └─ azd env set CHAT_AGENT_IMAGE
                                                          └─ persists tag for next run
```

## Resource Summary

| Component | Hub | Spoke |
|---|---|---|
| **VNet** | 10.0.0.0/16 | 10.1.0.0/16 |
| **Subnets** | snet-apim, snet-pe, snet-agent | snet-container-apps, snet-pe, snet-agent |
| **AI Foundry** | AI Services + Project + gpt-4o | AI Services + Project (no models) |
| **APIM** | StandardV2, VNet integrated | — |
| **Container Apps** | — | CAE + Chat Agent (private, PE only) |
| **ACR** | — | Container Registry (ACR Tasks) |
| **Observability** | Log Analytics + App Insights | (uses hub workspace) |
| **Private DNS** | 7 zones (linked to both VNets) | — |
| **Agent Service** | — | Capability Host + gateway connection → APIM |
