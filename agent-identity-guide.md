# Entra Agent Identity — Implementation Guide

This guide explains how to give an AI agent its own identity in Microsoft Entra, so it can access Azure resources (storage, AI models, etc.) without embedded credentials. It can be applied to any agent running in Azure or on other platforms.

## What is Agent Identity?

Agent Identity is a Microsoft Entra feature that gives AI agents their own security identity. Instead of using a shared service account or developer credentials, each agent gets a dedicated identity with its own permissions — following the principle of least privilege.

### Key Concepts

- **Blueprint** — A template that defines what type of agent this is. Think of it as a class definition. Credentials and trust relationships are configured here.
- **Agent Identity** — The actual runtime identity created from a Blueprint. This is what accesses resources. Azure RBAC roles are assigned to this identity.
- **Federated Identity Credential (FIC)** — A trust link between a compute identity (e.g., Container App managed identity) and the Blueprint, enabling credential-free authentication.

### How Authentication Works (in this sample)

```
Managed Identity → FIC → Blueprint → Agent Identity → Resource Token
```

1. The compute workload (Container App) authenticates using its managed identity
2. The FIC exchanges the MI token for a Blueprint token
3. The Blueprint token is exchanged for a resource token, specifying which Agent Identity to act as (`fmi_path`)
4. The final token's identity is the Agent Identity — Azure RBAC checks permissions against it

One Blueprint can have multiple Agent Identities, each with different resource access.

## Overview of Options

**Blueprint and Agent Identity setup** can be done via the [Agent 365 CLI](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-cli?tabs=linux) or directly through the Graph API. The CLI is convenient but not mandatory — the Graph API approach is more commonly used from a centralized management perspective.

**Authentication and token exchange** can be handled in multiple ways:
- The **auth sidecar** pattern, as shown in this repository
- A **custom token exchange** implementation, as demonstrated in [this Azure Functions example](https://github.com/ivanthelad/agentid-aiapp-fic/blob/main/demo-functions/function-app/function_app.py)
- A **direct SDK integration** via the Agent 365 SDK hosting capabilities (primarily for agents hosted through the SDK, not typical for custom agents)

**Observability** requires the Agent 365 SDK packages. This repository includes a working implementation — see the [Observability](#observability) section below.

| SDK | Used For |
|---|---|
| **LangChain / LangGraph** | AI agent with tool calling (inference) |
| **Microsoft Entra SDK for AgentID** | Auth sidecar (token exchange) |
| **Microsoft Agent 365 Observability** | Telemetry tracing for LangChain |
| **Azure AI Projects SDK** | Foundry Agent Service integration |

## Setup Steps

### Prerequisites

- A **management app registration** in Entra with the `Agent ID Administrator` role and `Application.ReadWrite.OwnedBy` Graph permission
- You can use either the [Agent 365 CLI](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-cli?tabs=linux) or the native Graph API for this process. The CLI provides additional features that may or may not be required — the choice depends on your implementation and process requirements.

The repository [jplck/aigw_lz](https://github.com/jplck/aigw_lz) provides a setup script that creates the Blueprint, Agent Identity, and permissions. You can use it or the CLI mentioned above.

### (Optional) Run the Setup Script

```bash
./scripts/setup_agent_identity.sh
```

The script performs these steps (all idempotent — safe to re-run):

1. **Creates a Blueprint** — Registers an `AgentIdentityBlueprint` app in Entra via Graph API
2. **Creates a Blueprint Service Principal** — Activates the Blueprint as a service principal
3. **Creates an Agent Identity** — Authenticates as the Blueprint (using a temporary secret) and creates an `AgentIdentity` service principal linked to it
4. **Creates a FIC** — Links the Container App's managed identity to the Blueprint so the sidecar can authenticate without credentials. This step is specific to the repository's Container App setup and needs to be adapted to your compute platform.

## Auth Sidecar (Optional)

The [Microsoft Entra SDK for AgentID](https://learn.microsoft.com/en-us/entra/msidweb/agent-id-sdk/overview) provides an auth sidecar container that handles the full token exchange chain. When enabled, it runs alongside the application and exposes a local HTTP API for token acquisition. It offloads the authentication overhead from your application by providing an authentication/authorization proxy as a sidecar to your container.

The application calls the sidecar to get tokens — **no auth code needed in the app itself**.

The sidecar is **optional**. You can also implement the token exchange directly using MSAL or other libraries. The sidecar approach is recommended because it centralizes all identity logic in a single container.

### How the App Uses It

The app calls `GET http://localhost:8080/AuthorizationHeaderUnauthenticated/{apiName}?AgentIdentity={id}` to get a Bearer token for any configured downstream API (Storage, CognitiveServices, etc.). The sidecar returns a ready-to-use authorization header.

## Observability

The [Microsoft Agent 365 SDK](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/agent-365-sdk?tabs=python) provides enterprise-grade extensions for AI agents. It includes observability packages for multiple frameworks — LangChain, OpenAI Agents SDK, Semantic Kernel, and Agent Framework — built on OpenTelemetry with structured spans for agent invocation, tool execution, and LLM inference.

Beyond observability, the SDK offers deeper integration capabilities for notifications, runtime utilities, and governed MCP (Model Context Protocol) tool server management. For a full example covering hosting, notifications, and more, see the [Agent365 CrewAI sample](https://github.com/microsoft/Agent365-Samples/tree/main/python/crewai/sample_agent).

This landing zone uses the observability-core and observability-extensions-langchain packages to automatically trace LangGraph agent executions. Telemetry is exported to the Agent365 backend using a token scoped to the Agent Identity. In this implementation, the token is acquired via the auth sidecar's `AgentToken` downstream API, but any authentication method that produces a valid Agent Identity token can be used instead.

## References

- [Entra Agent ID preview guide](https://github.com/astaykov/entra-agent-id-preview-guide)
- [Agent ID sidecar pattern](https://github.com/ivanthelad/agentid-aiapp-fic)
- [Microsoft Entra SDK for AgentID](https://learn.microsoft.com/en-us/entra/msidweb/agent-id-sdk/quickstart-python)
- [Microsoft Agent 365 Python SDK](https://github.com/microsoft/Agent365-python)
