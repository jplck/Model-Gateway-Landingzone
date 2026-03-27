"""Shared configuration — reads from environment variables."""

import os

APIM_GATEWAY_URL = os.environ.get("APIM_GATEWAY_URL", "")
APIM_API_KEY = os.environ.get("APIM_API_KEY", "")
DEPLOYMENT_NAME = os.environ.get("OPENAI_DEPLOYMENT_NAME", "gpt-4.1")
API_VERSION = os.environ.get("OPENAI_API_VERSION", "2025-03-01-preview")
AI_PROJECT_ENDPOINT = os.environ.get("AI_PROJECT_ENDPOINT", "")
GATEWAY_CONNECTION_NAME = os.environ.get("GATEWAY_CONNECTION_NAME", "apim-gateway")
AGENTID_SIDECAR_URL = os.environ.get("AGENTID_SIDECAR_URL", "")
STORAGE_ACCOUNT_URL = os.environ.get("STORAGE_ACCOUNT_URL", "")
STORAGE_CONTAINER_NAME = os.environ.get("STORAGE_CONTAINER_NAME", "agent-files")
AGENT_IDENTITY_APP_ID = os.environ.get("AGENT_IDENTITY_APP_ID", "")
AZURE_TENANT_ID = os.environ.get(
    "AZURE_TENANT_ID", os.environ.get("AzureAd__TenantId", "")
)
