#!/usr/bin/env bash
# --------------------------------------------------------------------------
# postprovision hook — builds the chat-agent image and deploys it
# Runs automatically after `azd provision` (or `azd up`).
# Solves the chicken-and-egg: ACR must exist before we can push an image.
# --------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${SCRIPT_DIR}/../apps/chat-agent"

# azd populates env vars from Bicep outputs (exact output names)
ACR_LOGIN_SERVER="${acrLoginServer:-}"
SPOKE_RG="${spokeResourceGroupName:-}"

if [[ -z "$ACR_LOGIN_SERVER" ]]; then
  echo "⏭️  acrLoginServer not set — skipping image build."
  exit 0
fi

# Derive registry name from login server (e.g. myacr.azurecr.io → myacr)
ACR_NAME="${ACR_LOGIN_SERVER%%.*}"

# Generate a unique tag based on timestamp
TAG="v$(date -u +%Y%m%d%H%M%S)"
IMAGE="${ACR_LOGIN_SERVER}/chat-agent:${TAG}"

echo "🔨 Building chat-agent image: ${IMAGE}"
az acr build \
  --registry "$ACR_NAME" \
  --image "chat-agent:${TAG}" \
  --image "chat-agent:latest" \
  "$APP_DIR" \
  --no-logs

# Find the container app name
CA_NAME=$(az containerapp list -g "$SPOKE_RG" --query "[0].name" -o tsv 2>/dev/null || true)

if [[ -n "$CA_NAME" ]]; then
  echo "🚀 Deploying ${IMAGE} to ${CA_NAME}"
  az containerapp update \
    --name "$CA_NAME" \
    --resource-group "$SPOKE_RG" \
    --image "$IMAGE" \
    --output none

  echo "✅ Container app updated to ${IMAGE}"
else
  echo "⚠️  No container app found in ${SPOKE_RG} — image built but not deployed."
fi

# Persist the image tag so the next `azd provision` uses it in Bicep
azd env set CHAT_AGENT_IMAGE "$IMAGE" 2>/dev/null || true
azd env set CHAT_AGENT_PORT "8000" 2>/dev/null || true

echo "📝 CHAT_AGENT_IMAGE=${IMAGE} saved to azd env"
