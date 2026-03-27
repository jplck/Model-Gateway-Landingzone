"""LangGraph ReAct agent with tools and blob storage integration."""

import json
import logging
import xml.etree.ElementTree as ET

import httpx
from langchain_openai import ChatOpenAI
from langchain_core.tools import tool
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage
from langgraph.prebuilt import create_react_agent

from config import (
    APIM_GATEWAY_URL,
    APIM_API_KEY,
    DEPLOYMENT_NAME,
    AGENTID_SIDECAR_URL,
    AGENT_IDENTITY_APP_ID,
    STORAGE_ACCOUNT_URL,
    STORAGE_CONTAINER_NAME,
)

logger = logging.getLogger("chat-agent")

# ---------------------------------------------------------------------------
# LLM
# ---------------------------------------------------------------------------

llm: ChatOpenAI | None = None

if APIM_GATEWAY_URL and APIM_API_KEY:
    llm = ChatOpenAI(
        base_url=f"{APIM_GATEWAY_URL.rstrip('/')}/openai/v1",
        api_key=APIM_API_KEY,
        model=DEPLOYMENT_NAME,
        use_responses_api=True,
        default_headers={"api-key": APIM_API_KEY},
    )
    logger.info("LangGraph LLM configured: %s via %s (Responses API)", DEPLOYMENT_NAME, APIM_GATEWAY_URL)
else:
    logger.warning("APIM_GATEWAY_URL or APIM_API_KEY not set — inference disabled")

# ---------------------------------------------------------------------------
# Blob storage helper (uses auth sidecar)
# ---------------------------------------------------------------------------


async def list_blobs(prefix: str = "") -> list[dict]:
    """Fetch blob list from spoke storage via the auth sidecar."""
    if not AGENTID_SIDECAR_URL or not STORAGE_ACCOUNT_URL:
        return []
    async with httpx.AsyncClient(timeout=15) as client:
        # Get authorization header from sidecar (app-only / autonomous agent flow)
        params = {}
        if AGENT_IDENTITY_APP_ID:
            params["AgentIdentity"] = AGENT_IDENTITY_APP_ID
        auth_resp = await client.get(
            f"{AGENTID_SIDECAR_URL}/AuthorizationHeaderUnauthenticated/Storage",
            params=params,
        )
        if auth_resp.status_code != 200:
            return []
        auth_header = auth_resp.json().get("authorizationHeader", "")
        if not auth_header:
            return []
        list_url = (
            f"{STORAGE_ACCOUNT_URL.rstrip('/')}/{STORAGE_CONTAINER_NAME}"
            f"?restype=container&comp=list&prefix={prefix}"
        )
        blob_resp = await client.get(
            list_url,
            headers={
                "Authorization": auth_header,
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
# LangChain tools
# ---------------------------------------------------------------------------


@tool
async def list_files(prefix: str = "") -> str:
    """List files in the agent's blob storage container.

    Returns file names, sizes, and content types.
    Use prefix to filter by path/folder (e.g. 'documents/' or 'images/photo').
    """
    blobs = await list_blobs(prefix=prefix)
    return json.dumps({"files": blobs, "count": len(blobs)})


_tools = []
if AGENTID_SIDECAR_URL and STORAGE_ACCOUNT_URL:
    _tools.append(list_files)

# ---------------------------------------------------------------------------
# Agent factory
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = (
    "You are a helpful assistant running in an AI Gateway landing zone. "
    "You have access to a blob storage container and can list files in it. "
    "Be concise and helpful."
)


def get_agent(model: str | None = None):
    """Create a LangGraph ReAct agent, optionally overriding the deployment."""
    agent_llm = llm
    if model and model != DEPLOYMENT_NAME and agent_llm is not None:
        agent_llm = ChatOpenAI(
            base_url=f"{APIM_GATEWAY_URL.rstrip('/')}/openai/v1",
            api_key=APIM_API_KEY,
            model=model,
            use_responses_api=True,
            default_headers={"api-key": APIM_API_KEY},
        )
    if agent_llm is None:
        return None
    return create_react_agent(agent_llm, _tools, prompt=SYSTEM_PROMPT)


def to_langchain_messages(messages):
    """Convert ChatMessage list to LangChain message objects."""
    lc_messages = []
    for m in messages:
        if m.role == "system":
            lc_messages.append(SystemMessage(content=m.content))
        elif m.role == "user":
            lc_messages.append(HumanMessage(content=m.content))
        elif m.role == "assistant":
            lc_messages.append(AIMessage(content=m.content))
    return lc_messages
