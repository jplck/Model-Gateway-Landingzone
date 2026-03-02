"""
Chat Agent — FastAPI + LangChain sample app for the AI Gateway Landing Zone.

Routes:
  GET  /           → Chat UI (static HTML)
  POST /api/chat   → LangChain chat endpoint (calls APIM → Foundry)
  GET  /health     → Health check
"""

import os
import logging

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel
from langchain_openai import AzureChatOpenAI
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("chat-agent")

app = FastAPI(title="Chat Agent", version="1.0.0")

# ---------------------------------------------------------------------------
# LangChain LLM — calls APIM gateway → hub Foundry model
# ---------------------------------------------------------------------------

APIM_GATEWAY_URL = os.environ.get("APIM_GATEWAY_URL", "")
APIM_API_KEY = os.environ.get("APIM_API_KEY", "")
DEPLOYMENT_NAME = os.environ.get("OPENAI_DEPLOYMENT_NAME", "gpt-4o")
API_VERSION = os.environ.get("OPENAI_API_VERSION", "2024-10-21")

llm: AzureChatOpenAI | None = None

if APIM_GATEWAY_URL and APIM_API_KEY:
    llm = AzureChatOpenAI(
        azure_endpoint=APIM_GATEWAY_URL,
        api_key=APIM_API_KEY,
        api_version=API_VERSION,
        azure_deployment=DEPLOYMENT_NAME,
        temperature=0.7,
        max_tokens=1024,
    )
    logger.info("LLM configured: %s via %s", DEPLOYMENT_NAME, APIM_GATEWAY_URL)
else:
    logger.warning(
        "APIM_GATEWAY_URL or APIM_API_KEY not set — /api/chat will return 503"
    )


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class ChatMessage(BaseModel):
    role: str  # "user", "assistant", "system"
    content: str


class ChatRequest(BaseModel):
    messages: list[ChatMessage]


class ChatResponse(BaseModel):
    reply: str


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
        "deployment": DEPLOYMENT_NAME,
        "gateway": APIM_GATEWAY_URL,
    }


@app.post("/api/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    if llm is None:
        raise HTTPException(
            status_code=503,
            detail="LLM not configured. Set APIM_GATEWAY_URL and APIM_API_KEY.",
        )

    lc_messages = []
    for m in req.messages:
        if m.role == "system":
            lc_messages.append(SystemMessage(content=m.content))
        elif m.role == "assistant":
            lc_messages.append(AIMessage(content=m.content))
        else:
            lc_messages.append(HumanMessage(content=m.content))

    try:
        response = await llm.ainvoke(lc_messages)
        return ChatResponse(reply=response.content)
    except Exception as e:
        logger.exception("LLM call failed")
        raise HTTPException(status_code=502, detail=f"LLM error: {e}")
