#!/usr/bin/env bash
# --------------------------------------------------------------------------
# postprovision — builds images and deploys agents
# Called by scripts/deploy.sh (Phase 5) with env vars already exported.
# --------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAT_APP_DIR="${SCRIPT_DIR}/../apps/chat-agent"

SUB_ID=$(az account show --query id -o tsv)
API_VERSION="2025-04-01-preview"

# --------------------------------------------------------------------------
# Capability Host creation
# VNet-injected caphosts can take 50+ minutes, exceeding ARM deployment
# timeout. We create them here via REST API with polling.
# --------------------------------------------------------------------------
create_caphost() {
  local rg="$1" account="$2" project="$3"
  local storage_conn="$4" search_conn="$5" cosmos_conn="$6"

  if [[ -z "$account" || -z "$project" ]]; then
    return 0
  fi

  local base="https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${rg}/providers/Microsoft.CognitiveServices"
  local acct_url="${base}/accounts/${account}/capabilityHosts/caphost?api-version=${API_VERSION}"
  local acct_list_url="${base}/accounts/${account}/capabilityHosts?api-version=${API_VERSION}"
  local proj_url="${base}/accounts/${account}/projects/${project}/capabilityHosts/caphost?api-version=${API_VERSION}"
  local proj_list_url="${base}/accounts/${account}/projects/${project}/capabilityHosts?api-version=${API_VERSION}"

  # Helper: check if any caphost exists (platform may rename "caphost" internally)
  caphost_state() {
    local list_url="$1"
    az rest --method get --url "$list_url" 2>/dev/null \
      | python3 -c "import sys,json; v=json.load(sys.stdin).get('value',[]); print(v[0]['properties']['provisioningState'] if v else 'NotFound')" 2>/dev/null || echo "NotFound"
  }

  # Account-level caphost
  local acct_state
  acct_state=$(caphost_state "$acct_list_url")
  if [[ "$acct_state" == "Succeeded" ]]; then
    echo "✅ Account caphost already exists ($account)"
  else
    echo "🔧 Creating account caphost for $account (this can take 20-60 minutes)..."
    az rest --method put --url "$acct_url" \
      --body '{"properties":{"capabilityHostKind":"Agents"}}' -o none 2>&1 || true
    # Poll until succeeded
    for i in $(seq 1 120); do
      acct_state=$(caphost_state "$acct_list_url")
      if [[ "$acct_state" == "Succeeded" ]]; then
        echo "✅ Account caphost created ($account)"
        break
      elif [[ "$acct_state" == "Failed" ]]; then
        echo "❌ Account caphost creation failed ($account)"
        return 1
      fi
      echo "   ⏳ State: $acct_state (waiting 30s, attempt $i/120)..."
      sleep 30
    done
  fi

  # Project-level caphost
  local proj_state
  proj_state=$(caphost_state "$proj_list_url")
  if [[ "$proj_state" == "Succeeded" ]]; then
    echo "✅ Project caphost already exists ($project)"
  else
    echo "🔧 Creating project caphost for $project..."
    az rest --method put --url "$proj_url" \
      --body "{\"properties\":{\"capabilityHostKind\":\"Agents\",\"vectorStoreConnections\":[\"${search_conn}\"],\"storageConnections\":[\"${storage_conn}\"],\"threadStorageConnections\":[\"${cosmos_conn}\"]}}" \
      -o none 2>&1 || true
    for i in $(seq 1 60); do
      proj_state=$(caphost_state "$proj_list_url")
      if [[ "$proj_state" == "Succeeded" ]]; then
        echo "✅ Project caphost created ($project)"
        break
      elif [[ "$proj_state" == "Failed" ]]; then
        echo "❌ Project caphost creation failed ($project)"
        return 1
      fi
      echo "   ⏳ State: $proj_state (waiting 15s, attempt $i/60)..."
      sleep 15
    done
  fi
}

HUB_RG="${hubResourceGroupName:-}"
HUB_ACCOUNT="${hubFoundryAccountName:-}"
HUB_PROJECT="${hubFoundryProjectName:-}"
HUB_STORAGE_CONN="${hubStorageConnectionName:-}"
HUB_SEARCH_CONN="${hubSearchConnectionName:-}"
HUB_COSMOS_CONN="${hubCosmosConnectionName:-}"

SPOKE_ACCOUNT="${spokeFoundryAccountName:-}"
SPOKE_PROJECT="${spokeFoundryProjectName:-}"
SPOKE_STORAGE_CONN="${spokeStorageConnectionName:-}"
SPOKE_SEARCH_CONN="${spokeSearchConnectionName:-}"
SPOKE_COSMOS_CONN="${spokeCosmosConnectionName:-}"

if [[ -n "$HUB_ACCOUNT" ]]; then
  create_caphost "$HUB_RG" "$HUB_ACCOUNT" "$HUB_PROJECT" \
    "$HUB_STORAGE_CONN" "$HUB_SEARCH_CONN" "$HUB_COSMOS_CONN"
fi

SPOKE_RG="${spokeResourceGroupName:-}"
if [[ -n "$SPOKE_ACCOUNT" ]]; then
  create_caphost "$SPOKE_RG" "$SPOKE_ACCOUNT" "$SPOKE_PROJECT" \
    "$SPOKE_STORAGE_CONN" "$SPOKE_SEARCH_CONN" "$SPOKE_COSMOS_CONN"
fi

# --------------------------------------------------------------------------
# Image build & deploy
# --------------------------------------------------------------------------
ACR_LOGIN_SERVER="${acrLoginServer:-}"
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

  echo "✅ Container app updated to ${IMAGE} (port 8000)"
else
  echo "⚠️  No container app found in ${SPOKE_RG} — image built but not deployed."
fi

echo "📝 CHAT_AGENT_IMAGE=${IMAGE}"


