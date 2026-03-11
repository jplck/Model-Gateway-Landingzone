"""Foundry Agent Service + Hosted Agent logic."""

import logging
import re

from config import AI_PROJECT_ENDPOINT, GATEWAY_CONNECTION_NAME

logger = logging.getLogger("chat-agent")

# ---------------------------------------------------------------------------
# Lazy-initialised Foundry SDK clients
# ---------------------------------------------------------------------------

_project_client = None
_openai_client = None
_agents: dict[str, object] = {}


def get_project_client():
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


def get_openai_client():
    global _openai_client
    if _openai_client is None:
        client = get_project_client()
        if client:
            _openai_client = client.get_openai_client()
            logger.info("OpenAI client obtained from project client")
    return _openai_client


def get_or_create_agent(model_ref: str):
    """Return cached agent or create a new PromptAgent for the given model."""
    if model_ref not in _agents:
        from azure.ai.projects.models import PromptAgentDefinition

        client = get_project_client()
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
# Foundry Agent chat
# ---------------------------------------------------------------------------


def agent_chat(message: str, model: str, thread_id: str | None = None):
    """Run a Foundry Agent chat turn. Returns (reply, thread_id)."""
    client = get_project_client()
    if not client:
        raise RuntimeError("Agent not configured. Set AI_PROJECT_ENDPOINT.")

    model_ref = f"{GATEWAY_CONNECTION_NAME}/{model}"
    agent = get_or_create_agent(model_ref)
    oai = get_openai_client()

    kwargs = {
        "model": model_ref,
        "input": message,
        "extra_body": {"agent_reference": {"name": agent.name, "type": "agent_reference"}},
    }
    if thread_id:
        kwargs["previous_response_id"] = thread_id

    conv = oai.responses.create(**kwargs)

    reply = ""
    for output in conv.output:
        if output.type == "message":
            for content in output.content:
                if content.type == "output_text":
                    reply = content.text

    return reply, conv.id
