"""
deploy_hosted_agent.py — Register a hosted agent image with Foundry.

Uses ImageBasedHostedAgentDefinition (same pattern as the msft-foundry-hosted-agents-sample).
The hosted agent uses BYO APIM gateway with dynamic model discovery.

Reads from environment:
  AI_PROJECT_ENDPOINT    — spoke Foundry project endpoint
  HOSTED_AGENT_IMAGE     — full ACR image tag (e.g. myacr.azurecr.io/hosted-agent:v123)
  APIM_GATEWAY_URL       — APIM gateway URL for the AOAI endpoint
  GATEWAY_CONNECTION_NAME— name of the apim-gateway connection (default: apim-gateway)
"""

import os
import sys

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    ImageBasedHostedAgentDefinition,
    ProtocolVersionRecord,
    AgentProtocol,
)
from azure.identity import DefaultAzureCredential


def main():
    project_endpoint = os.environ.get("AI_PROJECT_ENDPOINT", "")
    image_tag = os.environ.get("HOSTED_AGENT_IMAGE", "")
    apim_url = os.environ.get("APIM_GATEWAY_URL", "")
    gw_conn = os.environ.get("GATEWAY_CONNECTION_NAME", "apim-gateway")

    if not project_endpoint:
        print("⏭️  AI_PROJECT_ENDPOINT not set — skipping hosted agent deploy.")
        sys.exit(0)

    if not image_tag:
        print("⏭️  HOSTED_AGENT_IMAGE not set — skipping hosted agent deploy.")
        sys.exit(0)

    print(f"📦 Registering hosted agent image: {image_tag}")
    print(f"   Project: {project_endpoint}")

    credential = DefaultAzureCredential()
    client = AIProjectClient(
        endpoint=project_endpoint,
        credential=credential,
    )

    protocols = [ProtocolVersionRecord(protocol=AgentProtocol.RESPONSES, version="v2")]

    # Environment variables injected into the hosted agent container at runtime.
    # The agent uses these to configure the LangChain LLM (via init_chat_model).
    # The APIM gateway acts as the Azure OpenAI endpoint.
    env_vars = {
        "AZURE_AI_PROJECT_ENDPOINT": project_endpoint,
        "AZURE_AI_MODEL_DEPLOYMENT_NAME": "gpt-4o",
        "AZURE_OPENAI_ENDPOINT": f"{apim_url}/openai" if apim_url else "",
        "OPENAI_API_VERSION": "2024-10-21",
    }
    # Filter out empty values
    env_vars = {k: v for k, v in env_vars.items() if v}

    agent_name = "gw-hosted-agent"

    agent = client.agents.create_version(
        agent_name=agent_name,
        description="LangGraph hosted agent with tools (BYO APIM gateway, dynamic discovery)",
        definition=ImageBasedHostedAgentDefinition(
            container_protocol_versions=protocols,
            cpu="1",
            memory="2Gi",
            image=image_tag,
            environment_variables=env_vars,
        ),
    )

    print(f"✅ Hosted agent '{agent_name}' registered: {agent.id} (v{agent.version})")


if __name__ == "__main__":
    main()
