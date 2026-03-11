"""
Chat Agent — FastAPI app for the AI Gateway Landing Zone.

Routes:
  GET  /               → Chat UI (static HTML)
  GET  /api/models     → Discover deployed models via APIM gateway
  POST /api/chat       → LangGraph agent (tool calling)
  POST /api/agent/chat → Foundry Agent (Agent SDK v2)
  GET  /api/files      → List blobs in spoke storage
  GET  /api/auth/test  → Probe auth sidecar tokens
  GET  /health         → Health check
"""

import os
import logging

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

from config import (
    APIM_GATEWAY_URL,
    APIM_API_KEY,
    API_VERSION,
    DEPLOYMENT_NAME,
    AI_PROJECT_ENDPOINT,
    AGENTID_SIDECAR_URL,
    AGENT_IDENTITY_APP_ID,
    STORAGE_ACCOUNT_URL,
    STORAGE_CONTAINER_NAME,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("chat-agent")

app = FastAPI(title="Chat Agent", version="4.0.0")

# ---------------------------------------------------------------------------
# A365 Observability — traces LangChain calls to Agent365 backend
# ---------------------------------------------------------------------------

if AGENTID_SIDECAR_URL and AGENT_IDENTITY_APP_ID:
    try:
        import requests as _requests
        from microsoft_agents_a365.observability.core import configure as a365_configure
        from microsoft_agents_a365.observability.core.exporters.agent365_exporter_options import Agent365ExporterOptions
        from microsoft_agents_a365.observability.extensions.langchain import LangChainTracerInstrumentor

        def _a365_token_resolver(agent_id: str, tenant_id: str) -> str | None:
            """Resolve an AgentToken from the auth sidecar for A365 telemetry export."""
            try:
                resp = _requests.get(
                    f"{AGENTID_SIDECAR_URL}/api/token/AgentToken",
                    timeout=10,
                )
                if resp.status_code == 200:
                    return resp.json().get("access_token")
                logger.warning("Sidecar AgentToken request failed: %s", resp.status_code)
            except Exception as e:
                logger.warning("Failed to resolve A365 token: %s", e)
            return None

        a365_configure(
            service_name="chat-agent",
            service_namespace="aigw-landing-zone",
            exporter_options=Agent365ExporterOptions(
                token_resolver=_a365_token_resolver,
                cluster_category="prod",
            ),
        )

        LangChainTracerInstrumentor().instrument()
        logger.info("A365 observability configured (agent=%s)", AGENT_IDENTITY_APP_ID)
    except ImportError:
        logger.info("A365 observability packages not installed — skipping")
    except Exception as e:
        logger.warning("A365 observability setup failed: %s", e)

# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    messages: list[ChatMessage]
    model: str | None = None


class ToolCallInfo(BaseModel):
    name: str
    arguments: dict
    result: str


class ChatResponse(BaseModel):
    reply: str
    tool_calls: list[ToolCallInfo] = []


class AgentChatRequest(BaseModel):
    message: str
    model: str = "gpt-4o"
    thread_id: str | None = None


class AgentChatResponse(BaseModel):
    reply: str
    thread_id: str


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")


@app.get("/")
async def index():
    return FileResponse(os.path.join(STATIC_DIR, "index.html"))


@app.get("/health")
async def health():
    from inference import llm

    return {
        "status": "ok",
        "llm_configured": llm is not None,
        "agent_configured": bool(AI_PROJECT_ENDPOINT),
        "deployment": DEPLOYMENT_NAME,
        "gateway": APIM_GATEWAY_URL,
        "project_endpoint": AI_PROJECT_ENDPOINT,
        "sidecar_url": AGENTID_SIDECAR_URL or None,
    }


@app.get("/api/auth/test")
async def test_auth_sidecar():
    """Probe the Agent ID auth sidecar and attempt to acquire tokens."""
    if not AGENTID_SIDECAR_URL:
        return {"error": "AGENTID_SIDECAR_URL not configured"}

    results = {}
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            r = await client.get(f"{AGENTID_SIDECAR_URL}/health")
            results["sidecar_health"] = {"status": r.status_code, "body": r.text[:500]}
        except Exception as e:
            results["sidecar_health"] = {"error": str(e)}

        for api_name in ["CognitiveServices", "Storage", "AgentToken"]:
            try:
                r = await client.get(f"{AGENTID_SIDECAR_URL}/api/token/{api_name}")
                if r.status_code == 200:
                    token_data = r.json()
                    access_token = token_data.get("access_token", "")
                    results[api_name] = {
                        "status": "ok",
                        "token_length": len(access_token),
                        "token_prefix": access_token[:20] + "..." if access_token else "",
                    }
                else:
                    results[api_name] = {"status": r.status_code, "body": r.text[:500]}
            except Exception as e:
                results[api_name] = {"error": str(e)}

    return results


@app.get("/api/files")
async def list_files_endpoint(prefix: str = ""):
    """List blobs in the spoke storage container using a sidecar-acquired token."""
    from inference import list_blobs

    if not AGENTID_SIDECAR_URL:
        raise HTTPException(503, "Auth sidecar not configured")
    if not STORAGE_ACCOUNT_URL:
        raise HTTPException(503, "STORAGE_ACCOUNT_URL not configured")

    blobs = await list_blobs(prefix=prefix)
    return {"container": STORAGE_CONTAINER_NAME, "prefix": prefix, "blobs": blobs}


@app.get("/api/models")
async def list_models():
    """Discover deployed models via the APIM gateway's ARM-based discovery."""
    if not APIM_GATEWAY_URL or not APIM_API_KEY:
        raise HTTPException(503, "APIM not configured")

    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.get(
            f"{APIM_GATEWAY_URL}/openai/deployments?api-version={API_VERSION}",
            headers={"api-key": APIM_API_KEY},
        )
        if resp.status_code != 200:
            raise HTTPException(resp.status_code, f"Discovery failed: {resp.text}")

        data = resp.json()
        models = []
        for d in data.get("value", []):
            props = d.get("properties", {})
            model_info = props.get("model", {})
            models.append({
                "id": d.get("name", ""),
                "model": model_info.get("name", ""),
                "version": model_info.get("version", ""),
                "status": props.get("provisioningState", ""),
            })
        return {"models": models}


@app.post("/api/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    """LangGraph ReAct agent → APIM → Hub Foundry, with automatic tool calling."""
    from inference import get_agent, to_langchain_messages

    agent = get_agent(req.model)
    if agent is None:
        raise HTTPException(503, "LLM not configured. Set APIM_GATEWAY_URL and APIM_API_KEY.")

    messages = to_langchain_messages(req.messages)
    tool_calls_made: list[ToolCallInfo] = []

    try:
        result = await agent.ainvoke({"messages": messages})

        reply = ""
        for msg in result["messages"]:
            if hasattr(msg, "tool_calls") and msg.tool_calls:
                for tc in msg.tool_calls:
                    tool_calls_made.append(ToolCallInfo(
                        name=tc["name"],
                        arguments=tc.get("args", {}),
                        result="",
                    ))
            if msg.type == "tool" and tool_calls_made:
                for tci in tool_calls_made:
                    if tci.name == msg.name and tci.result == "":
                        tci.result = msg.content
                        break
            if msg.type == "ai" and msg.content:
                reply = msg.content

        return ChatResponse(reply=reply, tool_calls=tool_calls_made)
    except Exception as e:
        logger.exception("LangGraph agent call failed")
        raise HTTPException(502, f"LLM error: {e}")


@app.post("/api/agent/chat", response_model=AgentChatResponse)
def agent_chat_route(req: AgentChatRequest):
    """Chat via Foundry Agent Service → APIM Gateway → Hub Foundry."""
    from foundry_agent import agent_chat

    try:
        reply, thread_id = agent_chat(req.message, req.model, req.thread_id)
        return AgentChatResponse(reply=reply, thread_id=thread_id)
    except RuntimeError as e:
        raise HTTPException(503, str(e))
    except Exception as e:
        logger.exception("Agent call failed")
        raise HTTPException(502, f"Agent error: {e}")



