"""
Hosted Agent — Agent Framework agent for the AI Gateway Landing Zone.

Runs as a container image inside Foundry Agent Service.
Uses AzureAIAgentClient which routes model calls through Foundry
(supporting connections like apim-gateway for model access).

Framework: Microsoft Agent Framework
Adapter:   azure.ai.agentserver.agentframework (exposes Responses API v2)
"""

import asyncio
import os
import random
from datetime import datetime, timezone
from typing import Annotated

from dotenv import load_dotenv

load_dotenv(override=True)

from agent_framework import ai_function, ChatAgent
from agent_framework.azure import AzureAIAgentClient
from azure.ai.agentserver.agentframework import from_agent_framework
from azure.identity.aio import DefaultAzureCredential

# ---------------------------------------------------------------------------
# Configuration (injected by HostedAgentDefinition env vars)
# ---------------------------------------------------------------------------

PROJECT_ENDPOINT = os.getenv("AZURE_AI_PROJECT_ENDPOINT", "")
MODEL_DEPLOYMENT_NAME = os.getenv("AZURE_AI_MODEL_DEPLOYMENT_NAME", "gpt-4o")


# ---------------------------------------------------------------------------
# Tools — simple tools to demonstrate tool-calling
# ---------------------------------------------------------------------------


@ai_function
def get_current_time() -> str:
    """Return the current UTC time. Useful when the user asks what time it is."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


@ai_function
def roll_dice(sides: Annotated[int, "Number of sides on the dice (default 6)"] = 6) -> str:
    """Roll a dice with the given number of sides and return the result."""
    result = random.randint(1, max(1, sides))
    return f"Rolled a {sides}-sided dice: {result}"


@ai_function
def calculate(expression: Annotated[str, "A mathematical expression like '2 + 2' or '12 * 7'"]) -> str:
    """Evaluate a simple math expression and return the result."""
    try:
        allowed = set("0123456789+-*/.() ")
        if not all(c in allowed for c in expression):
            return "Error: expression contains invalid characters"
        result = eval(expression)  # noqa: S307 — restricted to digits+ops
        return str(result)
    except Exception as e:
        return f"Error: {e}"


# ---------------------------------------------------------------------------
# Entrypoint — expose via Foundry hosted agent adapter
# ---------------------------------------------------------------------------


async def main():
    async with (
        DefaultAzureCredential() as credential,
        AzureAIAgentClient(
            project_endpoint=PROJECT_ENDPOINT,
            model_deployment_name=MODEL_DEPLOYMENT_NAME,
            credential=credential,
        ) as client,
    ):
        agent = client.create_agent(
            name="GatewayHostedAgent",
            instructions=(
                "You are a helpful assistant running as a hosted agent "
                "inside the AI Gateway landing zone. You have access to "
                "tools: get_current_time, roll_dice, and calculate. "
                "Use them when appropriate. Be concise and friendly."
            ),
            tools=[get_current_time, roll_dice, calculate],
        )

        print("Hosted agent starting on port 8088...")
        server = from_agent_framework(agent)
        await server.run_async()


if __name__ == "__main__":
    asyncio.run(main())
