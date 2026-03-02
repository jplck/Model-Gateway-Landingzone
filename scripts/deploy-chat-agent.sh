#!/usr/bin/env bash
# ============================================================================
# deploy-chat-agent.sh — Build, push, and deploy the chat agent app
#
# Steps:
#   1. Get ACR login server from azd env
#   2. Build Docker image
#   3. Push to ACR
#   4. Set azd env vars for the image
#   5. Run azd provision (deploys infra + APIM chat API)
#   6. Print the chat frontend URL
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
# 3. Set azd env vars and provision
# ============================================================================
info "Setting azd environment variables..."
azd env set CHAT_AGENT_IMAGE "$FULL_IMAGE" 2>/dev/null
azd env set CHAT_AGENT_PORT "8000" 2>/dev/null
ok "Environment variables set"

info "Running azd provision (this deploys APIM chat API + updates container app)..."
azd provision --no-prompt
ok "Infrastructure provisioned"

# ============================================================================
# 4. Print results
# ============================================================================
echo ""
CHAT_URL=$(azd env get-value chatFrontendUrl 2>/dev/null | head -1) || true
APIM_URL=$(azd env get-value apimGatewayUrl 2>/dev/null | head -1) || true
APP_FQDN=$(azd env get-value sampleAppFqdn 2>/dev/null | head -1) || true

echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Chat Agent deployed successfully!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Chat via APIM:${NC}   ${CHAT_URL:-${APIM_URL}/chat/}"
echo -e "  ${CYAN}Direct app:${NC}      https://${APP_FQDN:-unknown}/"
echo -e "  ${CYAN}Health check:${NC}    ${CHAT_URL:-${APIM_URL}/chat/}health"
echo ""
echo -e "  Flow: Browser → APIM (/chat) → Container App → APIM (/openai) → Foundry (gpt-4o)"
echo ""
