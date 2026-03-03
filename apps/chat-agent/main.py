"""
Chat Agent — Dual-mode FastAPI app for the AI Gateway Landing Zone.

Modes:
  1. Direct Inference — OpenAI SDK → APIM → Hub Foundry (API key auth)
  2. Foundry Agent    — PromptAgent SDK → Agent Service → APIM Gateway → Hub Foundry

Routes:
  GET  /              → Chat UI (static HTML)
  GET  /api/models    → Discover deployed models via APIM gateway
  POST /api/chat      → Direct inference (OpenAI SDK)
  POST /api/agent/chat→ Foundry Agent (Agent SDK v2)
  GET  /health        → Health check
"""

import os
import logging

import httpx
from openai import AzureOpenAI
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("chat-agent")

app = FastAPI(title="Chat Agent", version="2.0.0")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

APIM_GATEWAY_URL = os.environ.get("APIM_GATEWAY_URL", "")
APIM_API_KEY = os.environ.get("APIM_API_KEY", "")
DEPLOYMENT_NAME = os.environ.get("OPENAI_DEPLOYMENT_NAME", "gpt-4o")
API_VERSION = os.environ.get("OPENAI_API_VERSION", "2024-10-21")
AI_PROJECT_ENDPOINT = os.environ.get("AI_PROJECT_ENDPOINT", "")
GATEWAY_CONNECTION_NAME = os.environ.get("GATEWAY_CONNECTION_NAME", "apim-gateway")

# ---------------------------------------------------------------------------
# Direct Inference — Azure OpenAI SDK (APIM API-key auth)
# ---------------------------------------------------------------------------

oai_direct: AzureOpenAI | None = None

if APIM_GATEWAY_URL and APIM_API_KEY:
    oai_direct = AzureOpenAI(
        azure_endpoint=APIM_GATEWAY_URL,
        api_key=APIM_API_KEY,
        api_version=API_VERSION,
    )
    logger.info("Direct OpenAI configured: %s via %s", DEPLOYMENT_NAME, APIM_GATEWAY_URL)
else:
    logger.warning(
        "APIM_GATEWAY_URL or APIM_API_KEY not set — /api/chat will return 503"
    )

# ---------------------------------------------------------------------------
# Foundry Agent — lazy-initialised SDK client (new PromptAgent + conversations)
# ---------------------------------------------------------------------------

_project_client = None
_openai_client = None
_agents: dict[str, object] = {}  # model_ref → agent object


def _get_project_client():
    global _project_client
    if _project_client is None and AI_PROJECT_ENDPOINT:
        from azure.ai.projects import AIProjectClient
        from azure.identity import DefaultAzureCredential

        _project_client = AIProjectClient(
            endpoint=AI_PROJECT_ENDPOINT,
            credential=DefaultAzureCredential(),
        )
        logger.info("Agent client configured: %s", AI_PROJECT_ENDPOINT)
    return _project_client


def _get_openai_client():
    global _openai_client
    if _openai_client is None:
        client = _get_project_client()
        if client:
            _openai_client = client.get_openai_client()
            logger.info("OpenAI client obtained from project client")
    return _openai_client


def _get_or_create_agent(model_ref: str):
    """Return cached agent or create a new PromptAgent for the given model."""
    if model_ref not in _agents:
        from azure.ai.projects.models import PromptAgentDefinition

        client = _get_project_client()
        import re
        safe = re.sub(r'[^a-zA-Z0-9-]', '-', model_ref)
        safe = re.sub(r'-+', '-', safe).strip('-')[:63]
        agent_name = f"chat-{safe}"
        agent = client.agents.create_version(
            agent_name=agent_name,
            definition=PromptAgentDefinition(
                model=model_ref,
                instructions=(
                    "You are a helpful assistant running through the AI Gateway "
                    "landing zone. Be concise and helpful."
                ),
            ),
        )
        _agents[model_ref] = agent
        logger.info("Created prompt agent %s (v%s) for model %s", agent_name, agent.version, model_ref)
    return _agents[model_ref]


# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------

class ChatMessage(BaseModel):
    role: str  # "user", "assistant", "system"
    content: str


class ChatRequest(BaseModel):
    messages: list[ChatMessage]


class ChatResponse(BaseModel):
    reply: str


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
    return {
        "status": "ok",
        "llm_configured": oai_direct is not None,
        "agent_configured": bool(AI_PROJECT_ENDPOINT),
        "deployment": DEPLOYMENT_NAME,
        "gateway": APIM_GATEWAY_URL,
        "project_endpoint": AI_PROJECT_ENDPOINT,
    }


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
        # ARM management API returns { "value": [...] }
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
def chat(req: ChatRequest):
    """Direct inference via OpenAI SDK → APIM → Hub Foundry."""
    if oai_direct is None:
        raise HTTPException(
            status_code=503,
            detail="LLM not configured. Set APIM_GATEWAY_URL and APIM_API_KEY.",
        )

    messages = [{"role": m.role, "content": m.content} for m in req.messages]

    try:
        response = oai_direct.chat.completions.create(
            model=DEPLOYMENT_NAME,
            messages=messages,
            temperature=0.7,
            max_tokens=1024,
        )
        return ChatResponse(reply=response.choices[0].message.content)
    except Exception as e:
        logger.exception("LLM call failed")
        raise HTTPException(status_code=502, detail=f"LLM error: {e}")


@app.post("/api/agent/chat", response_model=AgentChatResponse)
def agent_chat(req: AgentChatRequest):
    """Chat via Foundry Agent Service → APIM Gateway → Hub Foundry.

    Uses the new PromptAgent + conversations/responses pattern.
    Sync handler — FastAPI runs it in a threadpool automatically.
    """
    client = _get_project_client()
    if not client:
        raise HTTPException(503, "Agent not configured. Set AI_PROJECT_ENDPOINT.")

    model_ref = f"{GATEWAY_CONNECTION_NAME}/{req.model}"

    try:
        agent = _get_or_create_agent(model_ref)
        oai = _get_openai_client()

        # Create or reuse conversation
        if req.thread_id:
            conversation_id = req.thread_id
        else:
            conv = oai.responses.create(
                model=model_ref,
                input=req.message,
                extra_body={"agent_reference": {"name": agent.name, "type": "agent_reference"}},
            )
            reply = ""
            for output in conv.output:
                if output.type == "message":
                    for content in output.content:
                        if content.type == "output_text":
                            reply = content.text
            return AgentChatResponse(reply=reply, thread_id=conv.id)

        # Continue existing conversation
        conv = oai.responses.create(
            model=model_ref,
            input=req.message,
            previous_response_id=conversation_id,
            extra_body={"agent_reference": {"name": agent.name, "type": "agent_reference"}},
        )
        reply = ""
        for output in conv.output:
            if output.type == "message":
                for content in output.content:
                    if content.type == "output_text":
                        reply = content.text
        return AgentChatResponse(reply=reply, thread_id=conv.id)

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Agent call failed")
        raise HTTPException(502, f"Agent error: {e}")
