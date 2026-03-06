#!/usr/bin/env bash
# --------------------------------------------------------------------------
# postprovision hook — builds images and deploys agents
# Runs automatically after `azd provision` (or `azd up`).
# Solves the chicken-and-egg: ACR must exist before we can push an image.
# --------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAT_APP_DIR="${SCRIPT_DIR}/../apps/chat-agent"
HOSTED_APP_DIR="${SCRIPT_DIR}/../apps/hosted-agent"

# azd populates env vars from Bicep outputs (exact output names)
# Use eval to load them from azd env
eval "$(azd env get-values 2>/dev/null | tr -d '\r')"

ACR_LOGIN_SERVER="${acrLoginServer:-}"
SPOKE_RG="${spokeResourceGroupName:-}"
SPOKE_PROJECT="${spokeProjectEndpoint:-}"
APIM_URL="${apimGatewayUrl:-}"

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
  "$CHAT_APP_DIR" \
  --no-logs

# Find the container app name (retry — it may still be provisioning)
CA_NAME=""
for i in 1 2 3 4 5; do
  CA_NAME=$(az containerapp list -g "$SPOKE_RG" --query "[0].name" -o tsv 2>/dev/null | tr -d '\r' || true)
  if [[ -n "$CA_NAME" ]]; then
    break
  fi
  echo "⏳ Waiting for container app to appear (attempt $i/5)..."
  sleep 10
done

if [[ -n "$CA_NAME" ]]; then
  echo "🚀 Deploying ${IMAGE} to ${CA_NAME}"
  # Wait a moment for the revision to stabilize
  sleep 5
  # Ensure registry auth is configured (first deploy uses MCR placeholder, no registry set)
  az containerapp registry set \
    --name "$CA_NAME" \
    --resource-group "$SPOKE_RG" \
    --server "$ACR_LOGIN_SERVER" \
    --identity system \
    --output none
  az containerapp update \
    --name "$CA_NAME" \
    --resource-group "$SPOKE_RG" \
    --image "$IMAGE" \
    --set-env-vars "PORT=8000" \
    --output none
  az containerapp ingress update \
    --name "$CA_NAME" \
    --resource-group "$SPOKE_RG" \
    --target-port 8000 \
    --output none

  echo "✅ Container app updated to ${IMAGE} (port 8000)"
else
  echo "⚠️  No container app found in ${SPOKE_RG} — image built but not deployed."
fi

# Persist the image tag so the next `azd provision` uses it in Bicep
azd env set CHAT_AGENT_IMAGE "$IMAGE" 2>/dev/null || true
azd env set CHAT_AGENT_PORT "8000" 2>/dev/null || true

echo "📝 CHAT_AGENT_IMAGE=${IMAGE} saved to azd env"

# ==========================================================================
# Build & register hosted agent image (LangGraph container)
# ==========================================================================

HOSTED_IMAGE="${ACR_LOGIN_SERVER}/hosted-agent:${TAG}"

echo "🔨 Building hosted-agent image: ${HOSTED_IMAGE}"
az acr build \
  --registry "$ACR_NAME" \
  --image "hosted-agent:${TAG}" \
  --image "hosted-agent:latest" \
  "$HOSTED_APP_DIR" \
  --no-logs

azd env set HOSTED_AGENT_IMAGE "$HOSTED_IMAGE" 2>/dev/null || true
echo "📝 HOSTED_AGENT_IMAGE=${HOSTED_IMAGE} saved to azd env"

# Register the hosted agent with Foundry (HostedAgentDefinition)
if [[ -n "$SPOKE_PROJECT" ]]; then
  echo "📦 Registering hosted agent with Foundry..."
  export AI_PROJECT_ENDPOINT="$SPOKE_PROJECT"
  export HOSTED_AGENT_IMAGE="$HOSTED_IMAGE"
  export APIM_GATEWAY_URL="${APIM_URL}"

  pip install --quiet --pre "azure-ai-projects>=2.0.0b4" azure-identity 2>/dev/null || pip install --break-system-packages --quiet --pre "azure-ai-projects>=2.0.0b4" azure-identity 2>/dev/null || true
  python3 "${SCRIPT_DIR}/deploy_hosted_agent.py" || {
    echo "⚠️  Hosted agent registration failed — image built but not registered."
  }
else
  echo "⏭️  spokeProjectEndpoint not set — skipping hosted agent registration."
fi
