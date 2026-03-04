"""
Hosted Agent — Simple LangGraph agent for the AI Gateway Landing Zone.

Runs as a container image inside Foundry Agent Service.
Uses the BYO APIM gateway via the apim-gateway connection for model access
(dynamic discovery — no static model list).

Framework: LangGraph + LangChain
Adapter:   azure.ai.agentserver.langgraph (exposes Responses API v2)
"""

import os
import logging
import random
from datetime import datetime, timezone

from langchain.chat_models import init_chat_model
from langchain_core.messages import SystemMessage, ToolMessage
from langchain_core.tools import tool
from langgraph.graph import END, START, MessagesState, StateGraph
from typing_extensions import Literal
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.ai.agentserver.langgraph import from_langgraph

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("hosted-agent")

# ---------------------------------------------------------------------------
# Configuration (injected by ImageBasedHostedAgentDefinition env vars)
# ---------------------------------------------------------------------------

deployment_name = os.getenv("AZURE_AI_MODEL_DEPLOYMENT_NAME", "gpt-4o")

try:
    credential = DefaultAzureCredential()
    token_provider = get_bearer_token_provider(
        credential, "https://cognitiveservices.azure.com/.default"
    )
    llm = init_chat_model(
        f"azure_openai:{deployment_name}",
        azure_ad_token_provider=token_provider,
    )
    logger.info("LLM initialised: azure_openai:%s", deployment_name)
except Exception:
    logger.exception("Failed to initialise LLM")
    raise


# ---------------------------------------------------------------------------
# Tools — simple mock tools to demonstrate tool-calling via the gateway
# ---------------------------------------------------------------------------


@tool
def get_current_time() -> str:
    """Return the current UTC time. Useful when the user asks what time it is."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


@tool
def roll_dice(sides: int = 6) -> dict:
    """Roll a dice with the given number of sides.

    Args:
        sides: number of sides on the dice (default 6)
    """
    result = random.randint(1, max(1, sides))
    return {"sides": sides, "result": result}


@tool
def calculate(expression: str) -> str:
    """Evaluate a simple math expression and return the result.

    Args:
        expression: a mathematical expression like '2 + 2' or '12 * 7'
    """
    try:
        # Only allow safe math operations
        allowed = set("0123456789+-*/.() ")
        if not all(c in allowed for c in expression):
            return f"Error: expression contains invalid characters"
        result = eval(expression)  # noqa: S307 — restricted to digits+ops
        return str(result)
    except Exception as e:
        return f"Error: {e}"


# ---------------------------------------------------------------------------
# LangGraph — simple ReAct agent with tool loop
# ---------------------------------------------------------------------------

tools = [get_current_time, roll_dice, calculate]
tools_by_name = {t.name: t for t in tools}
llm_with_tools = llm.bind_tools(tools)


def llm_call(state: MessagesState):
    """LLM decides whether to call a tool or respond directly."""
    return {
        "messages": [
            llm_with_tools.invoke(
                [
                    SystemMessage(
                        content=(
                            "You are a helpful assistant running as a hosted agent "
                            "inside the AI Gateway landing zone. You have access to "
                            "tools: get_current_time, roll_dice, and calculate. "
                            "Use them when appropriate. Be concise and friendly."
                        )
                    )
                ]
                + state["messages"]
            )
        ]
    }


def tool_node(state: dict):
    """Execute tool calls made by the LLM."""
    result = []
    for tc in state["messages"][-1].tool_calls:
        fn = tools_by_name[tc["name"]]
        observation = fn.invoke(tc["args"])
        result.append(ToolMessage(content=str(observation), tool_call_id=tc["id"]))
    return {"messages": result}


def should_continue(state: MessagesState) -> Literal["Action", "__end__"]:
    """Route to tools if the LLM made a tool call, else end."""
    last = state["messages"][-1]
    if hasattr(last, "tool_calls") and last.tool_calls:
        return "Action"
    return END


def build_agent():
    graph = StateGraph(MessagesState)
    graph.add_node("llm_call", llm_call)
    graph.add_node("environment", tool_node)
    graph.add_edge(START, "llm_call")
    graph.add_conditional_edges(
        "llm_call",
        should_continue,
        {"Action": "environment", END: END},
    )
    graph.add_edge("environment", "llm_call")
    return graph.compile()


# ---------------------------------------------------------------------------
# Entrypoint — expose via Foundry hosted agent adapter
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    agent = build_agent()
    adapter = from_langgraph(agent)
    logger.info("Hosted agent starting on port 8088...")
    adapter.run()
