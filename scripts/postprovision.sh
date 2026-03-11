#!/usr/bin/env bash
# --------------------------------------------------------------------------
# postprovision hook — builds images and deploys agents
# Runs automatically after `azd provision` (or `azd up`).
# Solves the chicken-and-egg: ACR must exist before we can push an image.
# --------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAT_APP_DIR="${SCRIPT_DIR}/../apps/chat-agent"

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
    --container-name "chat-agent" \
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
# Write directly to .env file to avoid azd interactive prompts
AZD_ENV_FILE="$(azd env list -o json 2>/dev/null | python3 -c "import json,sys;envs=json.load(sys.stdin);print(next(e['dotEnvPath'] for e in envs if e.get('isDefault')))" 2>/dev/null || true)"
if [[ -n "$AZD_ENV_FILE" && -f "$AZD_ENV_FILE" ]]; then
  sed -i '/^CHAT_AGENT_IMAGE=/d; /^CHAT_AGENT_PORT=/d' "$AZD_ENV_FILE"
  echo "CHAT_AGENT_IMAGE=\"${IMAGE}\"" >> "$AZD_ENV_FILE"
  echo "CHAT_AGENT_PORT=\"8000\"" >> "$AZD_ENV_FILE"
fi

echo "📝 CHAT_AGENT_IMAGE=${IMAGE} saved to azd env"


