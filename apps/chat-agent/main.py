"""
Chat Agent — FastAPI app for the AI Gateway Landing Zone.

Modes:
  1. LangGraph Agent  — LangGraph ReAct agent → APIM → Hub Foundry (API key auth, with tools)
  2. Foundry Agent    — PromptAgent SDK → Agent Service → APIM Gateway → Hub Foundry
  3. Hosted Agent     — ImageBasedHostedAgent (LangGraph container) → APIM Gateway → Hub Foundry

Routes:
  GET  /               → Chat UI (static HTML)
  GET  /api/models     → Discover deployed models via APIM gateway
  POST /api/chat       → LangGraph agent (tool calling)
  POST /api/agent/chat → Foundry Agent (Agent SDK v2)
  POST /api/hosted/chat→ Hosted Agent (LangGraph image-based)
  GET  /health         → Health check
"""

import os
import json as _json
import logging
import xml.etree.ElementTree as ET

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("chat-agent")

app = FastAPI(title="Chat Agent", version="4.0.0")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

APIM_GATEWAY_URL = os.environ.get("APIM_GATEWAY_URL", "")
APIM_API_KEY = os.environ.get("APIM_API_KEY", "")
DEPLOYMENT_NAME = os.environ.get("OPENAI_DEPLOYMENT_NAME", "gpt-4.1")
API_VERSION = os.environ.get("OPENAI_API_VERSION", "2024-10-21")
AI_PROJECT_ENDPOINT = os.environ.get("AI_PROJECT_ENDPOINT", "")
GATEWAY_CONNECTION_NAME = os.environ.get("GATEWAY_CONNECTION_NAME", "apim-gateway")
AGENTID_SIDECAR_URL = os.environ.get("AGENTID_SIDECAR_URL", "")
STORAGE_ACCOUNT_URL = os.environ.get("STORAGE_ACCOUNT_URL", "")
STORAGE_CONTAINER_NAME = os.environ.get("STORAGE_CONTAINER_NAME", "agent-files")

# ---------------------------------------------------------------------------
# LangGraph ReAct Agent — AzureChatOpenAI → APIM → Hub Foundry
# ---------------------------------------------------------------------------

from langchain_openai import AzureChatOpenAI
from langchain_core.tools import tool
from langgraph.prebuilt import create_react_agent

llm: AzureChatOpenAI | None = None

if APIM_GATEWAY_URL and APIM_API_KEY:
    llm = AzureChatOpenAI(
        azure_endpoint=APIM_GATEWAY_URL,
        api_key=APIM_API_KEY,
        api_version=API_VERSION,
        azure_deployment=DEPLOYMENT_NAME,
    )
    logger.info("LangGraph LLM configured: %s via %s", DEPLOYMENT_NAME, APIM_GATEWAY_URL)
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


class HostedChatRequest(BaseModel):
    message: str
    model: str = "gpt-4o"
    thread_id: str | None = None


class HostedChatResponse(BaseModel):
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
        "llm_configured": llm is not None,
        "agent_configured": bool(AI_PROJECT_ENDPOINT),
        "hosted_agent_configured": bool(AI_PROJECT_ENDPOINT),
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
        # Check sidecar health
        try:
            r = await client.get(f"{AGENTID_SIDECAR_URL}/health")
            results["sidecar_health"] = {"status": r.status_code, "body": r.text[:500]}
        except Exception as e:
            results["sidecar_health"] = {"error": str(e)}

        # Try each downstream API token
        for api_name in ["CognitiveServices", "Storage", "AgentToken"]:
            try:
                r = await client.get(f"{AGENTID_SIDECAR_URL}/api/token/{api_name}")
                if r.status_code == 200:
                    token_data = r.json()
                    # Don't expose the full token — just confirm it works
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
    if not AGENTID_SIDECAR_URL:
        raise HTTPException(503, "Auth sidecar not configured")
    if not STORAGE_ACCOUNT_URL:
        raise HTTPException(503, "STORAGE_ACCOUNT_URL not configured")

    blobs = await _list_blobs(prefix=prefix)
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


async def _list_blobs(prefix: str = "") -> list[dict]:
    """Fetch blob list from spoke storage via the auth sidecar."""
    if not AGENTID_SIDECAR_URL or not STORAGE_ACCOUNT_URL:
        return []
    async with httpx.AsyncClient(timeout=15) as client:
        token_resp = await client.get(f"{AGENTID_SIDECAR_URL}/api/token/Storage")
        if token_resp.status_code != 200:
            return []
        access_token = token_resp.json().get("access_token", "")
        if not access_token:
            return []
        list_url = (
            f"{STORAGE_ACCOUNT_URL.rstrip('/')}/{STORAGE_CONTAINER_NAME}"
            f"?restype=container&comp=list&prefix={prefix}"
        )
        blob_resp = await client.get(
            list_url,
            headers={
                "Authorization": f"Bearer {access_token}",
                "x-ms-version": "2024-11-04",
            },
        )
        if blob_resp.status_code != 200:
            return []
        root = ET.fromstring(blob_resp.text)
        blobs = []
        for blob_el in root.findall(".//Blob"):
            name = blob_el.findtext("Name", "")
            props = blob_el.find("Properties")
            blobs.append({
                "name": name,
                "size": int(props.findtext("Content-Length", "0")) if props is not None else 0,
                "content_type": props.findtext("Content-Type", "") if props is not None else "",
            })
        return blobs


# ---------------------------------------------------------------------------
# LangChain Tools
# ---------------------------------------------------------------------------

@tool
async def list_files(prefix: str = "") -> str:
    """List files in the agent's blob storage container.

    Returns file names, sizes, and content types.
    Use prefix to filter by path/folder (e.g. 'documents/' or 'images/photo').
    """
    blobs = await _list_blobs(prefix=prefix)
    return _json.dumps({"files": blobs, "count": len(blobs)})


# Build tool list — only include tools whose backing services are configured
_tools = []
if AGENTID_SIDECAR_URL and STORAGE_ACCOUNT_URL:
    _tools.append(list_files)

SYSTEM_PROMPT = (
    "You are a helpful assistant running in an AI Gateway landing zone. "
    "You have access to a blob storage container and can list files in it. "
    "Be concise and helpful."
)


def _get_agent(model: str | None = None):
    """Create a LangGraph ReAct agent, optionally overriding the deployment."""
    agent_llm = llm
    if model and model != DEPLOYMENT_NAME and agent_llm is not None:
        agent_llm = AzureChatOpenAI(
            azure_endpoint=APIM_GATEWAY_URL,
            api_key=APIM_API_KEY,
            api_version=API_VERSION,
            azure_deployment=model,
        )
    if agent_llm is None:
        return None
    return create_react_agent(agent_llm, _tools, prompt=SYSTEM_PROMPT)


@app.post("/api/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    """LangGraph ReAct agent → APIM → Hub Foundry, with automatic tool calling."""
    agent = _get_agent(req.model)
    if agent is None:
        raise HTTPException(
            status_code=503,
            detail="LLM not configured. Set APIM_GATEWAY_URL and APIM_API_KEY.",
        )

    # Build LangGraph messages from request
    from langchain_core.messages import HumanMessage, AIMessage, SystemMessage
    messages = []
    for m in req.messages:
        if m.role == "system":
            messages.append(SystemMessage(content=m.content))
        elif m.role == "user":
            messages.append(HumanMessage(content=m.content))
        elif m.role == "assistant":
            messages.append(AIMessage(content=m.content))

    tool_calls_made: list[ToolCallInfo] = []

    try:
        result = await agent.ainvoke({"messages": messages})

        # Extract tool calls and final reply from the message history
        reply = ""
        for msg in result["messages"]:
            # Collect tool call info from AI messages
            if hasattr(msg, "tool_calls") and msg.tool_calls:
                for tc in msg.tool_calls:
                    tool_calls_made.append(ToolCallInfo(
                        name=tc["name"],
                        arguments=tc.get("args", {}),
                        result="",  # filled below
                    ))
            # Collect tool results
            if msg.type == "tool" and tool_calls_made:
                # Match to the last unfilled tool call
                for tci in tool_calls_made:
                    if tci.name == msg.name and tci.result == "":
                        tci.result = msg.content
                        break
            # Last AI message is the final reply
            if msg.type == "ai" and msg.content:
                reply = msg.content

        return ChatResponse(reply=reply, tool_calls=tool_calls_made)
    except Exception as e:
        logger.exception("LangGraph agent call failed")
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


# ---------------------------------------------------------------------------
# Hosted Agent — ImageBasedHostedAgent invoked via Responses API
# ---------------------------------------------------------------------------

HOSTED_AGENT_NAME = os.environ.get("HOSTED_AGENT_NAME", "gw-hosted-agent")


@app.post("/api/hosted/chat", response_model=HostedChatResponse)
def hosted_chat(req: HostedChatRequest):
    """Chat via Hosted Agent (LangGraph image) → APIM Gateway → Hub Foundry.

    The hosted agent is a container-based agent registered with Foundry
    as an ImageBasedHostedAgentDefinition. It runs a LangGraph agent
    with tools (get_current_time, roll_dice, calculate) and uses the
    BYO APIM gateway for model access.
    """
    client = _get_project_client()
    if not client:
        raise HTTPException(503, "Agent not configured. Set AI_PROJECT_ENDPOINT.")

    model_ref = f"{GATEWAY_CONNECTION_NAME}/{req.model}"

    try:
        oai = _get_openai_client()

        kwargs = {
            "model": model_ref,
            "input": req.message,
            "extra_body": {
                "agent_reference": {
                    "name": HOSTED_AGENT_NAME,
                    "type": "agent_reference",
                }
            },
        }
        if req.thread_id:
            kwargs["previous_response_id"] = req.thread_id

        conv = oai.responses.create(**kwargs)

        reply = ""
        for output in conv.output:
            if output.type == "message":
                for content in output.content:
                    if content.type == "output_text":
                        reply = content.text

        return HostedChatResponse(reply=reply, thread_id=conv.id)

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Hosted agent call failed")
        raise HTTPException(502, f"Hosted agent error: {e}")
