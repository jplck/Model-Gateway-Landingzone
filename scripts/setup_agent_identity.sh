#!/usr/bin/env bash
# --------------------------------------------------------------------------
# Setup Entra Agent Identity — Blueprint, Agent Identity, and FIC
#
# Creates the full Agent ID chain and links it to the Container App's
# managed identity via a Federated Identity Credential (FIC).
#
# After running this script, the auth sidecar can authenticate as the
# Agent Identity using: MI → FIC → Blueprint → Agent Identity → Resource Token
#
# Prerequisites:
#   - Azure CLI logged in to the target tenant
#   - Management app registration with Agent ID Administrator role
#   - Management app credentials in AGENT_MGMT_CLIENT_ID and AGENT_MGMT_CLIENT_SECRET
#   - Management app granted Microsoft Graph application permission Application.ReadWrite.OwnedBy
#   - Container App already deployed (run `azd up` first)
#   - azd env populated with Bicep outputs
#
# Usage:
#   ./scripts/setup_agent_identity.sh
# --------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Helper: parse JSON with python3 (no jq dependency)
json_val() {
  python3 -c "import json,sys; data=json.load(sys.stdin); value=data.get('$1', ''); print('' if value is None else value)"
}

# Load azd env values
eval "$(azd env get-values 2>/dev/null | tr -d '\r')"

TENANT_ID="${AZURE_TENANT_ID:-$(az account show --query tenantId -o tsv)}"
MI_PRINCIPAL_ID="${containerAppMiPrincipalId:-}"
SPONSOR_OBJECT_ID="${SPONSOR_OBJECT_ID:-}"
MGMT_CLIENT_ID="${AGENT_MGMT_CLIENT_ID:-${MANAGEMENT_APP_CLIENT_ID:-}}"
MGMT_CLIENT_SECRET="${AGENT_MGMT_CLIENT_SECRET:-${MANAGEMENT_APP_CLIENT_SECRET:-}}"

BLUEPRINT_NAME="${BLUEPRINT_DISPLAY_NAME:-AI Gateway Agent Blueprint}"
AGENT_NAME="${AGENT_DISPLAY_NAME:-AI Gateway Chat Agent}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Entra Agent Identity Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Tenant:     ${TENANT_ID}"
echo "  MI Principal: ${MI_PRINCIPAL_ID:-(not set)}"

if [[ -z "$MGMT_CLIENT_ID" || -z "$MGMT_CLIENT_SECRET" ]]; then
  echo ""
  echo "❌ Missing management app credentials."
  echo ""
  echo "Set these environment variables or azd env values and retry:"
  echo "  AGENT_MGMT_CLIENT_ID"
  echo "  AGENT_MGMT_CLIENT_SECRET"
  echo ""
  echo "This script follows the Entra Agent ID preview guide and uses"
  echo "a dedicated management app with client credentials for Graph calls."
  exit 1
fi

# --- Determine sponsor ---
if [[ -z "$SPONSOR_OBJECT_ID" ]]; then
  echo ""
  echo "  No SPONSOR_OBJECT_ID set. Using current logged-in user as sponsor."
  SPONSOR_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
  if [[ -z "$SPONSOR_OBJECT_ID" ]]; then
    echo "❌ Cannot determine sponsor. Set SPONSOR_OBJECT_ID and retry."
    exit 1
  fi
fi
SPONSOR_URI="https://graph.microsoft.com/v1.0/users/${SPONSOR_OBJECT_ID}"
echo "  Sponsor:    ${SPONSOR_OBJECT_ID}"
echo ""

# ---------------------------------------------------------------------------
# Acquire a Graph token using the management app's client credentials.
# This follows the Entra Agent ID preview guide and avoids delegated user
# permissions such as Directory.AccessAsUser.All, which Agent APIs reject.
# ---------------------------------------------------------------------------
echo "🔑 Acquiring Graph token from management app client credentials..."
GRAPH_TOKEN_RESP=$(curl -s -X POST \
  "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${MGMT_CLIENT_ID}" \
  -d "client_secret=${MGMT_CLIENT_SECRET}" \
  -d "scope=https://graph.microsoft.com/.default")

GRAPH_TOKEN=$(echo "$GRAPH_TOKEN_RESP" | json_val access_token)

if [[ -z "$GRAPH_TOKEN" ]]; then
  echo "❌ Failed to acquire management app token for Microsoft Graph."
  echo "$GRAPH_TOKEN_RESP"
  exit 1
fi

graph_api() {
  # Usage: graph_api METHOD URL [BODY]
  local method="$1" url="$2" body="${3:-}"
  local args=(-s -X "$method" "$url"
    -H "Authorization: Bearer ${GRAPH_TOKEN}"
    -H "Content-Type: application/json"
    -H "OData-Version: 4.0")
  if [[ -n "$body" ]]; then
    args+=(-d "$body")
  fi
  curl "${args[@]}"
}

# =========================================================================
# Step 1: Find or Create Agent Identity Blueprint
# =========================================================================
echo "1️⃣  Agent Identity Blueprint '${BLUEPRINT_NAME}'..."

# Check for existing Blueprint
EXISTING_BP=$(graph_api GET "https://graph.microsoft.com/beta/applications" \
  | python3 -c "
import json,sys
apps = json.load(sys.stdin).get('value',[])
for a in apps:
    if a.get('displayName') == '$BLUEPRINT_NAME' and a.get('@odata.type') == '#microsoft.graph.agentIdentityBlueprint':
        print(a['id'], a['appId'])
        break
" 2>/dev/null || true)

if [[ -n "$EXISTING_BP" ]]; then
  BLUEPRINT_OBJ_ID=$(echo "$EXISTING_BP" | awk '{print $1}')
  BLUEPRINT_APP_ID=$(echo "$EXISTING_BP" | awk '{print $2}')
  echo "  ✓ Found existing Blueprint"
  echo "    Object ID: ${BLUEPRINT_OBJ_ID}"
  echo "    App ID:    ${BLUEPRINT_APP_ID}"
else
  BLUEPRINT_RESP=$(graph_api POST "https://graph.microsoft.com/beta/applications/" "{
      \"@odata.type\": \"Microsoft.Graph.AgentIdentityBlueprint\",
      \"displayName\": \"${BLUEPRINT_NAME}\",
      \"sponsors@odata.bind\": [\"${SPONSOR_URI}\"]
    }")

  BLUEPRINT_OBJ_ID=$(echo "$BLUEPRINT_RESP" | json_val id)
  BLUEPRINT_APP_ID=$(echo "$BLUEPRINT_RESP" | json_val appId)

  if [[ -z "$BLUEPRINT_APP_ID" ]]; then
    echo "❌ Failed to create Blueprint:"
    echo "$BLUEPRINT_RESP"
    exit 1
  fi

  echo "  ✓ Blueprint created"
  echo "    Object ID: ${BLUEPRINT_OBJ_ID}"
  echo "    App ID:    ${BLUEPRINT_APP_ID}"
fi

# =========================================================================
# Step 2: Find or Create Blueprint Service Principal
# =========================================================================
echo ""
echo "2️⃣  Blueprint Service Principal..."

EXISTING_SP=$(graph_api GET "https://graph.microsoft.com/beta/servicePrincipals?\$filter=appId%20eq%20'${BLUEPRINT_APP_ID}'" \
  | python3 -c "import json,sys;vals=json.load(sys.stdin).get('value',[]); print(vals[0]['id'] if vals else '')" 2>/dev/null || true)

if [[ -n "$EXISTING_SP" ]]; then
  BP_SP_ID="$EXISTING_SP"
  echo "  ✓ Found existing SP: ${BP_SP_ID}"
else
  BP_SP_RESP=$(graph_api POST \
    "https://graph.microsoft.com/beta/serviceprincipals/graph.agentIdentityBlueprintPrincipal" \
    "{\"appId\": \"${BLUEPRINT_APP_ID}\"}")

  BP_SP_ID=$(echo "$BP_SP_RESP" | json_val id)

  if [[ -z "$BP_SP_ID" ]]; then
    echo "  ⚠️  Blueprint SP creation response:"
    echo "  $BP_SP_RESP"
    exit 1
  fi

  echo "  ✓ Blueprint SP created: ${BP_SP_ID}"
fi

# =========================================================================
# Step 3: Find or Create Agent Identity
# =========================================================================
echo ""
echo "3️⃣  Agent Identity '${AGENT_NAME}'..."

# Check for existing Agent Identity linked to this blueprint
EXISTING_AGENT=$(graph_api GET "https://graph.microsoft.com/beta/servicePrincipals?\$filter=appId%20eq%20'${BLUEPRINT_APP_ID}'" \
  | python3 -c "
import json,sys
# Look for Agent Identities whose agentAppId matches our Blueprint
# The Agent Identity has its own unique appId but links back via agentAppId
" 2>/dev/null || true)

# Search by display name and type
EXISTING_AGENT=$(graph_api GET "https://graph.microsoft.com/beta/servicePrincipals" \
  | python3 -c "
import json,sys
sps = json.load(sys.stdin).get('value',[])
for sp in sps:
    if sp.get('displayName') == '$AGENT_NAME' and sp.get('@odata.type') == '#microsoft.graph.agentIdentity':
        print(sp['id'], sp['appId'])
        break
" 2>/dev/null || true)

if [[ -n "$EXISTING_AGENT" ]]; then
  AGENT_IDENTITY_ID=$(echo "$EXISTING_AGENT" | awk '{print $1}')
  AGENT_IDENTITY_APP_ID=$(echo "$EXISTING_AGENT" | awk '{print $2}')
  echo "  ✓ Found existing Agent Identity"
  echo "    ID:     ${AGENT_IDENTITY_ID}"
  echo "    App ID: ${AGENT_IDENTITY_APP_ID}"
else
  echo "  Creating new Agent Identity..."

  # Add temporary client secret to Blueprint for authentication
  echo "  Adding temporary client secret to Blueprint..."
  SECRET_RESP=$(graph_api POST \
    "https://graph.microsoft.com/beta/applications/${BLUEPRINT_OBJ_ID}/addPassword" \
    "{
      \"passwordCredential\": {
        \"displayName\": \"Agent Identity Setup (temporary)\",
        \"endDateTime\": \"2026-09-10T23:59:59Z\"
      }
    }")

  BLUEPRINT_SECRET=$(echo "$SECRET_RESP" | json_val secretText)
  SECRET_KEY_ID=$(echo "$SECRET_RESP" | json_val keyId)

  if [[ -z "$BLUEPRINT_SECRET" ]]; then
    echo "  ⚠️  addPassword response:"
    echo "  $SECRET_RESP"
    exit 1
  fi

  echo "  ✓ Client secret created (keyId: ${SECRET_KEY_ID})"
  echo "  ⏳ Waiting 45s for credential replication..."
  sleep 45

  # Authenticate as the Blueprint and create Agent Identity with retries.
  MAX_RETRIES=5
  for attempt in $(seq 1 $MAX_RETRIES); do
    echo "  Attempt ${attempt}/${MAX_RETRIES}: Authenticating as Blueprint..."

    BP_TOKEN_RESP=$(curl -s -X POST \
      "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=client_credentials" \
      -d "client_id=${BLUEPRINT_APP_ID}" \
      -d "client_secret=${BLUEPRINT_SECRET}" \
      -d "scope=https://graph.microsoft.com/.default")

    BP_TOKEN=$(echo "$BP_TOKEN_RESP" | json_val access_token)

    if [[ -z "$BP_TOKEN" ]]; then
      echo "  ⚠️  Token request failed:"
      echo "  $BP_TOKEN_RESP"
      if [[ $attempt -lt $MAX_RETRIES ]]; then
        echo "  Retrying in 30s..."
        sleep 30
        continue
      fi
      echo "❌ Failed to authenticate as blueprint after ${MAX_RETRIES} attempts."
      exit 1
    fi

    AGENT_RESP=$(curl -s -X POST \
      "https://graph.microsoft.com/beta/serviceprincipals/Microsoft.Graph.AgentIdentity" \
      -H "Authorization: Bearer ${BP_TOKEN}" \
      -H "Content-Type: application/json" \
      -H "OData-Version: 4.0" \
      -d "{
        \"displayName\": \"${AGENT_NAME}\",
        \"agentAppId\": \"${BLUEPRINT_APP_ID}\",
        \"sponsors@odata.bind\": [\"${SPONSOR_URI}\"]
      }")

    AGENT_IDENTITY_ID=$(echo "$AGENT_RESP" | json_val id)
    AGENT_IDENTITY_APP_ID=$(echo "$AGENT_RESP" | json_val appId)

    if [[ -n "$AGENT_IDENTITY_APP_ID" && "$AGENT_IDENTITY_APP_ID" != "" ]]; then
      break
    fi

    ERROR_CODE=$(echo "$AGENT_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error',{}).get('code',''))" 2>/dev/null || true)
    if [[ "$ERROR_CODE" == "Authorization_IdentityNotFound" && $attempt -lt $MAX_RETRIES ]]; then
      echo "  ⚠️  Blueprint SP not yet recognized by Graph. Waiting 30s for replication..."
      sleep 30
      continue
    fi

    echo "❌ Failed to create Agent Identity:"
    echo "$AGENT_RESP"
    exit 1
  done

  echo "  ✓ Agent Identity created"
  echo "    ID:     ${AGENT_IDENTITY_ID}"
  echo "    App ID: ${AGENT_IDENTITY_APP_ID}"

  # Remove the temporary client secret
  echo "  Removing temporary client secret..."
  graph_api POST \
    "https://graph.microsoft.com/beta/applications/${BLUEPRINT_OBJ_ID}/removePassword" \
    "{\"keyId\": \"${SECRET_KEY_ID}\"}" > /dev/null 2>&1 || true
  echo "  ✓ Temporary secret removed"
fi

# =========================================================================
# Step 4: Link Container App Managed Identity via FIC
# =========================================================================
if [[ -n "$MI_PRINCIPAL_ID" ]]; then
  echo ""
  echo "4️⃣  Federated Identity Credential (MI → Blueprint)..."

  # Check if FIC already exists
  EXISTING_FIC=$(graph_api GET "https://graph.microsoft.com/beta/applications/${BLUEPRINT_OBJ_ID}/federatedIdentityCredentials" \
    | python3 -c "
import json,sys
fics = json.load(sys.stdin).get('value',[])
for f in fics:
    if f.get('subject') == '$MI_PRINCIPAL_ID':
        print(f['id'])
        break
" 2>/dev/null || true)

  if [[ -n "$EXISTING_FIC" ]]; then
    echo "  ✓ FIC already exists for MI ${MI_PRINCIPAL_ID}"
  else
    graph_api POST \
      "https://graph.microsoft.com/beta/applications/${BLUEPRINT_OBJ_ID}/federatedIdentityCredentials" \
      "{
        \"name\": \"container-app-managed-identity\",
        \"issuer\": \"https://login.microsoftonline.com/${TENANT_ID}/v2.0\",
        \"subject\": \"${MI_PRINCIPAL_ID}\",
        \"audiences\": [\"api://AzureADTokenExchange\"]
      }" > /dev/null

    echo "  ✓ FIC created: MI ${MI_PRINCIPAL_ID} → Blueprint"
  fi
else
  echo ""
  echo "4️⃣  ⏭️  Skipping FIC (containerAppMiPrincipalId not available)"
  echo "    Deploy the Container App first (azd up), then re-run this script."
fi

# =========================================================================
# Step 5: Save to azd env
# =========================================================================
echo ""
echo "5️⃣  Saving to azd env..."

azd env set AZURE_TENANT_ID "$TENANT_ID" 2>/dev/null || true
azd env set BLUEPRINT_APP_ID "$BLUEPRINT_APP_ID" 2>/dev/null || true
azd env set AGENT_IDENTITY_APP_ID "$AGENT_IDENTITY_APP_ID" 2>/dev/null || true
azd env set ENABLE_AUTH_SIDECAR "true" 2>/dev/null || true

echo "  ✓ Saved to azd env"

# =========================================================================
# Summary
# =========================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Agent Identity setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Blueprint App ID:        ${BLUEPRINT_APP_ID}"
echo "  Agent Identity App ID:   ${AGENT_IDENTITY_APP_ID}"
echo "  Agent Identity ID:       ${AGENT_IDENTITY_ID}"
echo "  MI Principal ID (FIC):   ${MI_PRINCIPAL_ID:-(not linked)}"
echo ""
echo "  Next steps:"
echo "    1. Run 'azd up' to redeploy with the auth sidecar enabled"
echo "    2. The sidecar handles the full token exchange automatically:"
echo "       MI → FIC → Blueprint → Agent Identity → Resource Token"
echo ""
echo "  To grant resource access to the Agent Identity:"
echo "    az role assignment create \\"
echo "      --assignee-object-id ${AGENT_IDENTITY_ID} \\"
echo "      --assignee-principal-type ServicePrincipal \\"
echo "      --role 'Cognitive Services User' \\"
echo "      --scope <foundry-account-resource-id>"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
