#!/usr/bin/env bash
# ============================================================================
# test-gateway.sh — Smoke-test the AI Gateway Landing Zone
#
# Tests:
#   1. Resolve deployment outputs (APIM URL, subscription key, endpoints)
#   2. Health check: APIM gateway reachability
#   3. Responses via APIM → Foundry (gpt-4o) — external
#   4. Embeddings via APIM → Foundry (if deployment exists)
#   5. Error handling: invalid key, wrong deployment
#   6. Spoke Container App — env vars & internal model call via exec
#   7. Rate-limit validation (optional, with --test-ratelimit)
#   8. Sample Container App reachability
#
# Usage:
#   ./scripts/test-gateway.sh                    # run all smoke tests
#   ./scripts/test-gateway.sh --test-ratelimit   # include rate-limit test
#   ./scripts/test-gateway.sh --skip-spoke       # skip spoke exec tests
# ============================================================================

set -euo pipefail

# --- Colors ---------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

pass() { echo -e "  ${GREEN}✓ PASS${NC}: $1"; }
fail() { echo -e "  ${RED}✗ FAIL${NC}: $1"; FAILURES=$((FAILURES + 1)); }
info() { echo -e "  ${CYAN}ℹ${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
header() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

FAILURES=0
TEST_RATELIMIT=false
SKIP_SPOKE=false

# Portable JSON value extractor (no jq dependency)
# Usage: json_val '{"key":"val"}' key
json_val() {
  local json="$1" key="$2"
  echo "$json" | grep -o "\"${key}\":[^,}]*" | head -1 | sed 's/"'"${key}"'"://;s/^[[:space:]]*//;s/"//g'
}

for arg in "$@"; do
  case "$arg" in
    --test-ratelimit) TEST_RATELIMIT=true ;;
    --skip-spoke) SKIP_SPOKE=true ;;
  esac
done

# ============================================================================
# 1. Resolve deployment outputs
# ============================================================================
header "Resolving deployment outputs"

APIM_GATEWAY_URL=$(azd env get-value apimGatewayUrl 2>/dev/null | head -1) || true
HUB_RG=$(azd env get-value hubResourceGroupName 2>/dev/null | head -1) || true
SPOKE_RG=$(azd env get-value spokeResourceGroupName 2>/dev/null | head -1) || true
FOUNDRY_ENDPOINT=$(azd env get-value foundryEndpoint 2>/dev/null | head -1) || true
SAMPLE_APP_FQDN=$(azd env get-value sampleAppFqdn 2>/dev/null | head -1) || true

if [[ -z "$APIM_GATEWAY_URL" || -z "$HUB_RG" ]]; then
  echo -e "${RED}ERROR: Could not read azd environment values. Run 'azd up' first.${NC}"
  exit 1
fi

# Get APIM name from resource group
APIM_NAME=$(az apim list -g "$HUB_RG" --query "[0].name" -o tsv 2>/dev/null | tr -d '\r') || true
if [[ -z "$APIM_NAME" ]]; then
  echo -e "${RED}ERROR: Could not find APIM instance in $HUB_RG${NC}"
  exit 1
fi

# Get APIM subscription key
APIM_ID=$(az apim show -n "$APIM_NAME" -g "$HUB_RG" --query id -o tsv 2>/dev/null | tr -d '\r')
SUB_KEY=$(az rest --method post \
  --url "${APIM_ID}/subscriptions/spoke-subscription/listSecrets?api-version=2024-05-01" \
  --query primaryKey -o tsv 2>/dev/null | tr -d '\r') || true

if [[ -z "$SUB_KEY" ]]; then
  echo -e "${RED}ERROR: Could not retrieve APIM subscription key${NC}"
  exit 1
fi

info "APIM Gateway : $APIM_GATEWAY_URL"
info "APIM Name    : $APIM_NAME"
info "Hub RG       : $HUB_RG"
info "Spoke RG     : $SPOKE_RG"
info "Foundry      : $FOUNDRY_ENDPOINT"
info "Sample App   : ${SAMPLE_APP_FQDN:-'(not set)'}"
pass "Deployment outputs resolved"

# ============================================================================
# 2. APIM gateway reachability
# ============================================================================
header "APIM Gateway reachability"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  "${APIM_GATEWAY_URL}/status-0123456789abcdef" 2>/dev/null) || HTTP_CODE="000"

if [[ "$HTTP_CODE" == "200" ]]; then
  pass "APIM gateway is reachable (HTTP $HTTP_CODE)"
else
  # APIM returns 404 for unknown paths which still proves reachability
  if [[ "$HTTP_CODE" =~ ^(401|403|404)$ ]]; then
    pass "APIM gateway is reachable (HTTP $HTTP_CODE — expected for unauthenticated request)"
  else
    fail "APIM gateway returned HTTP $HTTP_CODE"
  fi
fi

# ============================================================================
# 3. Responses
# ============================================================================
header "Responses (gpt-4o)"

CHAT_RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 30 \
  -X POST "${APIM_GATEWAY_URL}/openai/deployments/gpt-4o/responses?api-version=2025-03-01-preview" \
  -H "api-key: ${SUB_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "input": "Reply with exactly: GATEWAY_TEST_OK",
    "max_output_tokens": 20,
    "temperature": 0
  }' 2>/dev/null) || CHAT_RESPONSE=$'\n000'

CHAT_HTTP_CODE=$(echo "$CHAT_RESPONSE" | tail -1)
CHAT_BODY=$(echo "$CHAT_RESPONSE" | sed '$d')

if [[ "$CHAT_HTTP_CODE" == "200" ]]; then
  CONTENT=$(echo "$CHAT_BODY" | grep -o '"text":"[^"]*"' | head -1 | sed 's/"text":"//;s/"$//')
  MODEL=$(json_val "$CHAT_BODY" model)
  TOKENS=$(json_val "$CHAT_BODY" total_tokens)
  info "Model: $MODEL | Tokens: $TOKENS"
  info "Response: $CONTENT"
  pass "Responses API working (HTTP 200)"
elif [[ "$CHAT_HTTP_CODE" == "429" ]]; then
  warn "Rate limited (HTTP 429) — the gateway is working but throttled"
  pass "Responses API endpoint is functional (rate limited)"
elif [[ "$CHAT_HTTP_CODE" =~ ^(401|403)$ ]]; then
  fail "Auth error (HTTP $CHAT_HTTP_CODE) — RBAC may still be propagating, retry in a few minutes"
  info "Response: $CHAT_BODY"
else
  fail "Responses API returned HTTP $CHAT_HTTP_CODE"
  info "Response: $(echo "$CHAT_BODY" | head -c 300)"
fi

# ============================================================================
# 4. Embeddings (best-effort — only if an embeddings model is deployed)
# ============================================================================
header "Embeddings (best-effort)"

EMB_RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 30 \
  -X POST "${APIM_GATEWAY_URL}/openai/deployments/text-embedding-ada-002/embeddings?api-version=2025-03-01-preview" \
  -H "api-key: ${SUB_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"input": "test embedding"}' 2>/dev/null) || EMB_RESPONSE=$'\n000'

EMB_HTTP_CODE=$(echo "$EMB_RESPONSE" | tail -1)

if [[ "$EMB_HTTP_CODE" == "200" ]]; then
  pass "Embeddings working (HTTP 200)"
elif [[ "$EMB_HTTP_CODE" == "404" ]]; then
  info "No embeddings model deployed — skipped (HTTP 404)"
else
  info "Embeddings returned HTTP $EMB_HTTP_CODE — no embeddings model may be deployed"
fi

# ============================================================================
# 5. Error handling — invalid key & wrong deployment
# ============================================================================
header "Error handling"

# 5a. Invalid API key should be rejected
BAD_KEY_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 \
  -X POST "${APIM_GATEWAY_URL}/openai/deployments/gpt-4o/responses?api-version=2025-03-01-preview" \
  -H "api-key: invalid-key-12345" \
  -H "Content-Type: application/json" \
  -d '{"input":"hi","max_output_tokens":1}' 2>/dev/null) || BAD_KEY_CODE="000"

if [[ "$BAD_KEY_CODE" == "401" ]]; then
  pass "Invalid API key rejected (HTTP 401)"
elif [[ "$BAD_KEY_CODE" == "403" ]]; then
  pass "Invalid API key rejected (HTTP 403)"
else
  fail "Invalid API key returned unexpected HTTP $BAD_KEY_CODE (expected 401/403)"
fi

# 5b. Non-existent deployment should return 404
BAD_DEPLOY_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 \
  -X POST "${APIM_GATEWAY_URL}/openai/deployments/nonexistent-model/responses?api-version=2025-03-01-preview" \
  -H "api-key: ${SUB_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"input":"hi","max_output_tokens":1}' 2>/dev/null) || BAD_DEPLOY_CODE="000"

if [[ "$BAD_DEPLOY_CODE" == "404" ]]; then
  pass "Non-existent deployment rejected (HTTP 404)"
else
  warn "Non-existent deployment returned HTTP $BAD_DEPLOY_CODE (expected 404)"
fi

# ============================================================================
# 6. Spoke Container App — validate env vars point to APIM gateway
# ============================================================================
if [[ "$SKIP_SPOKE" == "false" ]]; then
  header "Spoke → APIM configuration"

  # Get container app name
  CA_NAME=$(az containerapp list -g "$SPOKE_RG" --query "[0].name" -o tsv 2>/dev/null | tr -d '\r') || true

  if [[ -z "$CA_NAME" ]]; then
    warn "No Container App found in $SPOKE_RG — skipping spoke tests"
  else
    info "Container App: $CA_NAME"

    # Get env vars in a single call as TSV lines: "name\tvalue"
    CA_ENVS=$(az containerapp list -g "$SPOKE_RG" \
      --query "[0].properties.template.containers[0].env[].{n:name,v:value}" \
      -o tsv 2>/dev/null | tr -d '\r') || CA_ENVS=""

    CA_APIM_URL=$(echo "$CA_ENVS" | grep "^APIM_GATEWAY_URL" | awk '{print $2}')
    CA_OPENAI_BASE=$(echo "$CA_ENVS" | grep "^OPENAI_API_BASE" | awk '{print $2}')

    if [[ -n "$CA_APIM_URL" && "$CA_APIM_URL" == "$APIM_GATEWAY_URL" ]]; then
      pass "APIM_GATEWAY_URL env var correct ($CA_APIM_URL)"
    elif [[ -n "$CA_APIM_URL" ]]; then
      fail "APIM_GATEWAY_URL mismatch: expected $APIM_GATEWAY_URL, got $CA_APIM_URL"
    else
      fail "APIM_GATEWAY_URL env var not set on container app"
    fi

    if [[ -n "$CA_OPENAI_BASE" && "$CA_OPENAI_BASE" == "${APIM_GATEWAY_URL}/openai" ]]; then
      pass "OPENAI_API_BASE env var correct ($CA_OPENAI_BASE)"
    elif [[ -n "$CA_OPENAI_BASE" ]]; then
      fail "OPENAI_API_BASE mismatch: expected ${APIM_GATEWAY_URL}/openai, got $CA_OPENAI_BASE"
    else
      fail "OPENAI_API_BASE env var not set on container app"
    fi
  fi
else
  header "Spoke tests"
  info "Skipped (--skip-spoke)"
fi

# ============================================================================
# 7. Rate-limit validation (optional)
# ============================================================================
if [[ "$TEST_RATELIMIT" == "true" ]]; then
  header "Rate-limit validation (sending rapid requests)"
  info "Sending 10 rapid requests to check rate limiting..."

  RATE_LIMITED=false
  for i in $(seq 1 10); do
    RL_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
      -X POST "${APIM_GATEWAY_URL}/openai/deployments/gpt-4o/responses?api-version=2025-03-01-preview" \
      -H "api-key: ${SUB_KEY}" \
      -H "Content-Type: application/json" \
      -d '{"input":"hi","max_output_tokens":1}' 2>/dev/null) || RL_CODE="000"
    if [[ "$RL_CODE" == "429" ]]; then
      RATE_LIMITED=true
      info "Request $i: HTTP 429 (rate limited)"
      break
    else
      info "Request $i: HTTP $RL_CODE"
    fi
  done

  if [[ "$RATE_LIMITED" == "true" ]]; then
    pass "Rate limiting is active"
  else
    warn "No 429 received in 10 requests — rate limit may be higher than test volume"
  fi
fi

# ============================================================================
# 8. Chat Agent via APIM (end-to-end spoke → hub flow)
# ============================================================================
header "Chat Agent via APIM"

CHAT_FRONTEND_URL=$(azd env get-value chatFrontendUrl 2>/dev/null | head -1) || true

if [[ -n "$CHAT_FRONTEND_URL" ]]; then
  # 8a. Frontend reachable through APIM
  CHAT_FE_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 \
    "${CHAT_FRONTEND_URL}" 2>/dev/null) || CHAT_FE_CODE="000"

  if [[ "$CHAT_FE_CODE" == "200" ]]; then
    pass "Chat frontend reachable via APIM (HTTP 200)"
  elif [[ "$CHAT_FE_CODE" == "000" ]]; then
    warn "Chat frontend timed out via APIM"
  else
    fail "Chat frontend via APIM returned HTTP $CHAT_FE_CODE"
  fi

  # 8b. Health check
  CHAT_HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 \
    "${CHAT_FRONTEND_URL}health" 2>/dev/null) || CHAT_HEALTH_CODE="000"

  if [[ "$CHAT_HEALTH_CODE" == "200" ]]; then
    pass "Chat agent health check OK (HTTP 200)"
  else
    info "Chat agent health returned HTTP $CHAT_HEALTH_CODE"
  fi

  # 8c. End-to-end chat: APIM → Container App → APIM → Foundry
  CHAT_E2E_RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 30 \
    -X POST "${CHAT_FRONTEND_URL}api/chat" \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"Reply with exactly: E2E_TEST_OK"}]}' \
    2>/dev/null) || CHAT_E2E_RESPONSE=$'\n000'

  CHAT_E2E_CODE=$(echo "$CHAT_E2E_RESPONSE" | tail -1)
  CHAT_E2E_BODY=$(echo "$CHAT_E2E_RESPONSE" | sed '$d')

  if [[ "$CHAT_E2E_CODE" == "200" ]]; then
    CHAT_REPLY=$(echo "$CHAT_E2E_BODY" | grep -o '"reply":"[^"]*"' | head -1 | sed 's/"reply":"//;s/"$//')
    info "E2E reply: $CHAT_REPLY"
    pass "End-to-end spoke → APIM → Foundry chat working (HTTP 200)"
  elif [[ "$CHAT_E2E_CODE" == "503" ]]; then
    warn "Chat agent LLM not configured (HTTP 503) — deploy with ./scripts/deploy-chat-agent.sh"
  else
    fail "End-to-end chat returned HTTP $CHAT_E2E_CODE"
    info "Response: $(echo "$CHAT_E2E_BODY" | head -c 300)"
  fi
else
  info "Chat frontend URL not set — run ./scripts/deploy-chat-agent.sh first"
fi

# ============================================================================
# 9. Sample Container App
# ============================================================================
header "Sample Container App"

if [[ -n "${SAMPLE_APP_FQDN:-}" ]]; then
  APP_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    "https://${SAMPLE_APP_FQDN}/" 2>/dev/null) || APP_HTTP="000"

  if [[ "$APP_HTTP" =~ ^(200|301|302)$ ]]; then
    pass "Sample app is reachable (HTTP $APP_HTTP)"
  elif [[ "$APP_HTTP" == "000" ]]; then
    warn "Sample app timed out — may still be scaling up from zero"
  else
    info "Sample app returned HTTP $APP_HTTP (placeholder app — may not serve on /)"
  fi
else
  info "Sample app FQDN not set — skipped"
fi

# ============================================================================
# Summary
# ============================================================================
header "Summary"
if [[ "$FAILURES" -eq 0 ]]; then
  echo -e "\n  ${GREEN}All tests passed!${NC}\n"
  exit 0
else
  echo -e "\n  ${RED}${FAILURES} test(s) failed.${NC}\n"
  exit 1
fi
