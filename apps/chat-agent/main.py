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

import json
import os
import logging
import uuid

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
    AZURE_TENANT_ID,
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
        from microsoft_agents_a365.observability.core import (
            AgentDetails,
            BaggageBuilder,
            InvokeAgentScope,
            InvokeAgentDetails,
            InferenceScope,
            InferenceCallDetails,
            InferenceOperationType,
            ExecuteToolScope,
            ToolCallDetails,
            ToolType,
            TenantDetails,
            ExecutionType,
            Request as A365Request,
        )
        from microsoft_agents_a365.observability.extensions.langchain import CustomLangChainInstrumentor

        _a365_available = True

        def _a365_token_resolver(agent_id: str, tenant_id: str) -> str | None:
            """Resolve an AgentToken from the auth sidecar for A365 telemetry export."""
            try:
                params = {}
                if AGENT_IDENTITY_APP_ID:
                    params["AgentIdentity"] = AGENT_IDENTITY_APP_ID
                resp = _requests.get(
                    f"{AGENTID_SIDECAR_URL}/AuthorizationHeaderUnauthenticated/AgentToken",
                    params=params,
                    timeout=10,
                )
                if resp.status_code == 200:
                    header = resp.json().get("authorizationHeader", "")
                    return header.replace("Bearer ", "") if header else None
                logger.warning("Sidecar AgentToken request failed: %s", resp.status_code)
            except Exception as e:
                logger.warning("Failed to resolve A365 token: %s", e)
            return None

        a365_configure(
            service_name="chat-agent",
            service_namespace="aigw-landing-zone",
            token_resolver=_a365_token_resolver,
            cluster_category="prod",
        )

        CustomLangChainInstrumentor()
        logger.info("A365 observability configured (agent=%s)", AGENT_IDENTITY_APP_ID)
    except ImportError as e:
        _a365_available = False
        logger.info("A365 observability packages not installed — skipping: %s", e)
    except Exception as e:
        _a365_available = False
        logger.warning("A365 observability setup failed: %s", e)
else:
    _a365_available = False

# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------


def _extract_text(content) -> str:
    """Extract plain text from message content (string or Responses API content blocks)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("text"):
                parts.append(block["text"])
            elif isinstance(block, str):
                parts.append(block)
        return "".join(parts)
    return str(content)


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
            r = await client.get(f"{AGENTID_SIDECAR_URL}/healthz")
            results["sidecar_health"] = {"status": r.status_code, "body": r.text[:500]}
        except Exception as e:
            results["sidecar_health"] = {"error": str(e)}

        params = {}
        if AGENT_IDENTITY_APP_ID:
            params["AgentIdentity"] = AGENT_IDENTITY_APP_ID

        for api_name in ["CognitiveServices", "Storage", "AgentToken"]:
            try:
                r = await client.get(
                    f"{AGENTID_SIDECAR_URL}/AuthorizationHeaderUnauthenticated/{api_name}",
                    params=params,
                )
                if r.status_code == 200:
                    data = r.json()
                    header = data.get("authorizationHeader", "")
                    results[api_name] = {
                        "status": "ok",
                        "token_length": len(header),
                        "token_prefix": header[:27] + "..." if header else "",
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
    user_input = messages[-1].content if messages else ""
    tool_calls_made: list[ToolCallInfo] = []
    deployment = req.model or DEPLOYMENT_NAME

    if not _a365_available:
        return await _run_chat_agent(agent, messages, tool_calls_made)

    # Build A365 observability context
    correlation_id = str(uuid.uuid4())
    tenant_id = AZURE_TENANT_ID or "unknown"
    obs_agent_id = AGENT_IDENTITY_APP_ID or "chat-agent"

    tenant_details = TenantDetails(tenant_id=tenant_id)
    agent_details = AgentDetails(
        agent_id=obs_agent_id,
        agent_name="chat-agent",
        agent_description="AI Gateway Landing Zone LangGraph Chat Agent",
        tenant_id=tenant_id,
    )
    invoke_details = InvokeAgentDetails(
        details=agent_details,
        session_id=correlation_id,
    )
    a365_request = A365Request(
        content=user_input,
        execution_type=ExecutionType.HUMAN_TO_AGENT,
    )

    try:
        with BaggageBuilder() \
            .tenant_id(tenant_id) \
            .agent_id(obs_agent_id) \
            .correlation_id(correlation_id) \
            .build():

            with InvokeAgentScope.start(
                invoke_agent_details=invoke_details,
                tenant_details=tenant_details,
                request=a365_request,
            ) as invoke_scope:
                invoke_scope.record_input_messages([user_input])

                # Run the agent inside an InferenceScope
                inference_details = InferenceCallDetails(
                    operationName=InferenceOperationType.CHAT,
                    model=deployment,
                    providerName="Azure OpenAI via APIM",
                )

                with InferenceScope.start(
                    details=inference_details,
                    agent_details=agent_details,
                    tenant_details=tenant_details,
                    request=a365_request,
                ) as inference_scope:
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
                                    tci.result = _extract_text(msg.content)
                                    break
                        if msg.type == "ai" and msg.content:
                            reply = _extract_text(msg.content)

                    # Record token usage if available from the last AI message
                    last_ai = next(
                        (m for m in reversed(result["messages"]) if m.type == "ai"),
                        None,
                    )
                    if last_ai and hasattr(last_ai, "usage_metadata") and last_ai.usage_metadata:
                        usage = last_ai.usage_metadata
                        input_tokens = usage.get("input_tokens") or usage.get("prompt_tokens")
                        output_tokens = usage.get("output_tokens") or usage.get("completion_tokens")
                        if input_tokens:
                            inference_scope.record_input_tokens(input_tokens)
                        if output_tokens:
                            inference_scope.record_output_tokens(output_tokens)

                    inference_scope.record_finish_reasons(["stop"])
                    inference_scope.record_output_messages([reply])

                # Record tool calls as ExecuteToolScopes
                for tc in tool_calls_made:
                    tool_details = ToolCallDetails(
                        tool_name=tc.name,
                        arguments=json.dumps(tc.arguments),
                        tool_type=ToolType.FUNCTION.value,
                    )
                    with ExecuteToolScope.start(
                        details=tool_details,
                        agent_details=agent_details,
                        tenant_details=tenant_details,
                    ) as tool_scope:
                        tool_scope.record_response(tc.result)

                invoke_scope.record_output_messages([reply])

        return ChatResponse(reply=reply, tool_calls=tool_calls_made)
    except Exception as e:
        logger.exception("LangGraph agent call failed")
        raise HTTPException(502, f"LLM error: {e}")


async def _run_chat_agent(agent, messages, tool_calls_made):
    """Run LangGraph agent without A365 observability scopes (fallback)."""
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
                        tci.result = _extract_text(msg.content)
                        break
            if msg.type == "ai" and msg.content:
                reply = _extract_text(msg.content)

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

