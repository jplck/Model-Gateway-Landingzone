"""
deploy_hosted_agent.py — Register a hosted agent image with Foundry.

Uses HostedAgentDefinition from azure-ai-projects SDK (>= 2.0.0b4).
The hosted agent uses BYO APIM gateway with dynamic model discovery.

Requires: pip install --pre "azure-ai-projects>=2.0.0b4"

Reads from environment:
  AI_PROJECT_ENDPOINT    — spoke Foundry project endpoint
  HOSTED_AGENT_IMAGE     — full ACR image tag (e.g. myacr.azurecr.io/hosted-agent:v123)
  APIM_GATEWAY_URL       — APIM gateway URL for the AOAI endpoint
"""

import os
import sys

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import HostedAgentDefinition, ProtocolVersionRecord, AgentProtocol
from azure.identity import DefaultAzureCredential


def main():
    project_endpoint = os.environ.get("AI_PROJECT_ENDPOINT", "")
    image_tag = os.environ.get("HOSTED_AGENT_IMAGE", "")
    apim_url = os.environ.get("APIM_GATEWAY_URL", "")

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
        headers={"Foundry-Features": "HostedAgents=V1Preview"},
    )

    # Environment variables injected into the hosted agent container at runtime.
    # The agent calls Foundry's OpenAI endpoint, which routes via the
    # apim-gateway connection (registered on the account with the subscription key).
    # Extract the account OpenAI endpoint from the project endpoint.
    # project_endpoint: https://<account>.services.ai.azure.com/api/projects/<project>
    account_name = project_endpoint.split("//")[1].split(".")[0]
    foundry_openai_endpoint = f"https://{account_name}.openai.azure.com"

    env_vars = {
        "AZURE_AI_PROJECT_ENDPOINT": project_endpoint,
        "AZURE_AI_MODEL_DEPLOYMENT_NAME": "apim-gateway/gpt-4.1",
        "AZURE_OPENAI_ENDPOINT": foundry_openai_endpoint,
        "OPENAI_API_VERSION": "2024-10-21",
    }

    agent_name = "gw-hosted-agent"

    agent = client.agents.create_version(
        agent_name=agent_name,
        description="LangGraph hosted agent with tools (BYO APIM gateway)",
        definition=HostedAgentDefinition(
            container_protocol_versions=[ProtocolVersionRecord(protocol=AgentProtocol.RESPONSES, version="v2")],
            cpu="1",
            memory="2Gi",
            image=image_tag,
            environment_variables=env_vars,
        ),
    )

    print(f"✅ Hosted agent '{agent_name}' registered: {agent.id} (v{agent.version})")


if __name__ == "__main__":
    main()
