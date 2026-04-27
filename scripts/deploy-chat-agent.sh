#!/usr/bin/env bash
# ============================================================================
# deploy-chat-agent.sh — Build, push, and deploy the chat agent app
#
# Steps:
#   1. Get ACR login server from azd env
#   2. Build and push image via ACR Tasks (cloud build)
#   3. Update container app revision (fast, no full azd provision)
#   4. Print the chat frontend URL (via APIM — app is internal)
#
# Usage:
#   ./scripts/deploy-chat-agent.sh
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${CYAN}→${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1"; exit 1; }

APP_DIR="$(cd "$(dirname "$0")/../apps/chat-agent" && pwd)"
IMAGE_TAG="chat-agent:latest"

# ============================================================================
# 1. Get ACR login server
# ============================================================================
info "Reading deployment outputs..."
ACR_LOGIN_SERVER=$(azd env get-value acrLoginServer 2>/dev/null | head -1) || true
SPOKE_RG=$(azd env get-value spokeResourceGroupName 2>/dev/null | head -1) || true

if [[ -z "$ACR_LOGIN_SERVER" ]]; then
  err "ACR login server not found. Run 'azd up' first to deploy the infrastructure."
fi

FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_TAG}"
info "ACR: $ACR_LOGIN_SERVER"
info "Image: $FULL_IMAGE"

# ============================================================================
# 2. Build and push using ACR Tasks (no local Docker required)
# ============================================================================
ACR_NAME="${ACR_LOGIN_SERVER%%.*}"

info "Building and pushing image via ACR Tasks (cloud build)..."
az acr build \
  --registry "$ACR_NAME" \
  --image "$IMAGE_TAG" \
  "$APP_DIR" \
  --no-logs 2>/dev/null && ok "Image built and pushed: $FULL_IMAGE" || err "ACR build failed"

# ============================================================================
# 3. Update container app revision (fast — no full azd provision needed)
# ============================================================================
CA_NAME=$(azd env get-value sampleAppName 2>/dev/null | head -1) || true
APIM_URL=$(azd env get-value apimGatewayUrl 2>/dev/null | head -1) || true
APIM_KEY=$(azd env get-value spokeSubscriptionKey 2>/dev/null | head -1) || true

if [[ -z "$CA_NAME" || -z "$SPOKE_RG" ]]; then
  err "Container app name or spoke RG not found. Run 'azd up' first."
fi

info "Updating container app secrets..."
az containerapp secret set \
  --name "$CA_NAME" \
  --resource-group "$SPOKE_RG" \
  --secrets "apim-subscription-key=$APIM_KEY" \
  --output none 2>/dev/null
ok "Secrets updated"

info "Updating container app with new image..."
az containerapp update \
  --name "$CA_NAME" \
  --resource-group "$SPOKE_RG" \
  --image "$FULL_IMAGE" \
  --set-env-vars \
    "APIM_GATEWAY_URL=${APIM_URL}" \
    "APIM_API_KEY=secretref:apim-subscription-key" \
    "OPENAI_DEPLOYMENT_NAME=gpt-4.1" \
    "OPENAI_API_VERSION=2025-03-01-preview" \
  --container-name chat-agent \
  --output none 2>/dev/null
ok "Container app updated"

# ============================================================================
# 4. Also set azd env vars for future azd provision runs
# ============================================================================
info "Saving image config to azd env..."
azd env set CHAT_AGENT_IMAGE "$FULL_IMAGE" 2>/dev/null
azd env set CHAT_AGENT_PORT "8000" 2>/dev/null
ok "Environment variables saved"

# ============================================================================
# 5. Print results
# ============================================================================
echo ""
CHAT_URL="${APIM_URL}/chat/"

echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Chat Agent deployed successfully!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Chat via APIM:${NC}   ${CHAT_URL}"
echo -e "  ${CYAN}Health check:${NC}    ${CHAT_URL}health"
echo ""
echo -e "  Note: Container app ingress is internal — access only via APIM."
echo -e "  Flow: Browser → APIM (/chat) → Container App (internal) → APIM (/openai) → Foundry"
echo ""
