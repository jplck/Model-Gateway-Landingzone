#!/usr/bin/env bash
# --------------------------------------------------------------------------
# Phased deployment for AI Gateway Landing Zone
#
# Deploys infrastructure in 4 sequential phases to avoid ARM race conditions
# (AI Services networkInjections must complete before PE creation).
#
# Phases:
#   1. networking.bicep   — RGs, VNets, subnets, peering, DNS zones
#   2. hub.bicep          — Observability, Foundry core, APIM
#   3. spoke.bicep        — Container Apps, spoke Foundry core (optional)
#   4. connectivity.bicep — Foundry PEs, APIM Chat API, DNS wildcard, RBAC
#   5. postprovision.sh   — Capability hosts (REST API) + image build
#
# Usage:
#   ./scripts/deploy.sh              # Full deploy
#   ./scripts/deploy.sh --phase 4    # Start from phase 4
#
# Prerequisites:
#   - az login (authenticated Azure CLI)
#   - Environment variables or .env file
# --------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
INFRA_DIR="${ROOT_DIR}/infra"

# Parse --phase argument
START_PHASE=1
while [[ $# -gt 0 ]]; do
  case $1 in
    --phase) START_PHASE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Load env vars from .env
if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a; source "${ROOT_DIR}/.env"; set +a
fi

LOCATION="${AZURE_LOCATION:-swedencentral}"
ENV_NAME="${AZURE_ENV_NAME:-dev}"
PROJECT_NAME="${PROJECT_NAME:-aigw}"
HUB_RG="${AZURE_HUB_RESOURCE_GROUP:-rg-${ENV_NAME}-${PROJECT_NAME}-hub}"
SPOKE_RG="${AZURE_SPOKE_RESOURCE_GROUP:-rg-${ENV_NAME}-${PROJECT_NAME}-spoke}"
DEPLOY_SPOKE_FOUNDRY="${DEPLOY_SPOKE_FOUNDRY:-true}"
PUBLISHER_EMAIL="${APIM_PUBLISHER_EMAIL:-admin@contoso.com}"
PUBLISHER_NAME="${APIM_PUBLISHER_NAME:-AI Gateway Team}"
CHAT_IMAGE="${CHAT_AGENT_IMAGE:-mcr.microsoft.com/azuredocs/containerapps-helloworld:latest}"
CHAT_PORT="${CHAT_AGENT_PORT:-80}"
ENABLE_AUTH_SIDECAR="${ENABLE_AUTH_SIDECAR:-false}"
TENANT_ID="${AZURE_TENANT_ID:-}"
BLUEPRINT_APP_ID="${BLUEPRINT_APP_ID:-}"
AGENT_IDENTITY_APP_ID="${AGENT_IDENTITY_APP_ID:-}"
ENABLE_A365="${ENABLE_A365_OBSERVABILITY:-false}"

TS=$(date -u +%Y%m%dT%H%M%S)

# Helper: extract a single output value from deployment JSON
get_output() {
  echo "$1" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$2',{}).get('value',''))" 2>/dev/null
}

# Helper: find the latest deployment by prefix
latest_deployment() {
  az deployment sub list --query "[?starts_with(name,'$1')].name | sort(@) | [-1]" -o tsv 2>/dev/null
}

# =========================================================================
# Phase 1 — Networking
# =========================================================================
if [[ "$START_PHASE" -le 1 ]]; then
  echo ""
  echo "========================================"
  echo "  Phase 1: Networking"
  echo "========================================"
  echo ""

  NET_OUT=$(az deployment sub create \
    --name "aigw-networking-${TS}" \
    --location "$LOCATION" \
    --template-file "${INFRA_DIR}/networking.bicep" \
    --parameters \
      location="$LOCATION" \
      environmentName="$ENV_NAME" \
      projectName="$PROJECT_NAME" \
      hubResourceGroupName="$HUB_RG" \
      spokeResourceGroupName="$SPOKE_RG" \
      deploySpokeFoundry="$DEPLOY_SPOKE_FOUNDRY" \
    --query 'properties.outputs' -o json)

  echo "✅ Phase 1 complete"
else
  echo "⏭️  Skipping phase 1 — reading existing networking outputs..."
  NET_OUT=$(az deployment sub show \
    --name "$(latest_deployment 'aigw-networking-')" \
    --query 'properties.outputs' -o json 2>/dev/null || echo '{}')
fi

# Extract networking outputs
HUB_APIM_SUBNET=$(get_output "$NET_OUT" hubApimSubnetId)
HUB_PE_SUBNET=$(get_output "$NET_OUT" hubPrivateEndpointSubnetId)
HUB_AGENT_SUBNET=$(get_output "$NET_OUT" hubAgentSubnetId)
SPOKE_CA_SUBNET=$(get_output "$NET_OUT" spokeContainerAppsSubnetId)
SPOKE_PE_SUBNET=$(get_output "$NET_OUT" spokePrivateEndpointSubnetId)
SPOKE_AGENT_SUBNET=$(get_output "$NET_OUT" spokeAgentSubnetId)
COG_DNS_ZONE=$(get_output "$NET_OUT" cognitiveServicesDnsZoneId)
OAI_DNS_ZONE=$(get_output "$NET_OUT" openAiDnsZoneId)
AIS_DNS_ZONE=$(get_output "$NET_OUT" aiServicesDnsZoneId)
BLOB_DNS_ZONE=$(get_output "$NET_OUT" storageBlobDnsZoneId)
SEARCH_DNS_ZONE=$(get_output "$NET_OUT" searchDnsZoneId)
COSMOS_DNS_ZONE=$(get_output "$NET_OUT" cosmosDnsZoneId)
CAE_DNS_ZONE_ID=$(get_output "$NET_OUT" containerAppsDnsZoneId)
CAE_DNS_ZONE_NAME=$(get_output "$NET_OUT" containerAppsDnsZoneName)

# =========================================================================
# Phase 2 — Hub
# =========================================================================
if [[ "$START_PHASE" -le 2 ]]; then
  echo ""
  echo "========================================"
  echo "  Phase 2: Hub Services"
  echo "========================================"
  echo ""

  HUB_OUT=$(az deployment sub create \
    --name "aigw-hub-${TS}" \
    --location "$LOCATION" \
    --template-file "${INFRA_DIR}/hub.bicep" \
    --parameters \
      location="$LOCATION" \
      environmentName="$ENV_NAME" \
      projectName="$PROJECT_NAME" \
      hubResourceGroupName="$HUB_RG" \
      publisherEmail="$PUBLISHER_EMAIL" \
      publisherName="$PUBLISHER_NAME" \
      hubAgentSubnetId="$HUB_AGENT_SUBNET" \
      hubApimSubnetId="$HUB_APIM_SUBNET" \
    --query 'properties.outputs' -o json)

  echo "✅ Phase 2 complete"
else
  echo "⏭️  Skipping phase 2 — reading existing hub outputs..."
  HUB_OUT=$(az deployment sub show \
    --name "$(latest_deployment 'aigw-hub-')" \
    --query 'properties.outputs' -o json 2>/dev/null || echo '{}')
fi

# Extract hub outputs
LAW_ID=$(get_output "$HUB_OUT" logAnalyticsWorkspaceId)
LAW_CUSTOMER_ID=$(get_output "$HUB_OUT" logAnalyticsCustomerId)
LAW_SHARED_KEY=$(get_output "$HUB_OUT" logAnalyticsSharedKey)
APPI_CONN_STR=$(get_output "$HUB_OUT" appInsightsConnectionString)
APIM_NAME=$(get_output "$HUB_OUT" apimName)
APIM_GW_URL=$(get_output "$HUB_OUT" apimGatewayUrl)
SPOKE_SUB_KEY=$(get_output "$HUB_OUT" spokeSubscriptionKey)
HUB_FOUNDRY_ACCOUNT=$(get_output "$HUB_OUT" hubFoundryAccountName)
HUB_FOUNDRY_PROJECT=$(get_output "$HUB_OUT" hubFoundryProjectName)
HUB_STORAGE_CONN=$(get_output "$HUB_OUT" hubStorageConnectionName)
HUB_SEARCH_CONN=$(get_output "$HUB_OUT" hubSearchConnectionName)
HUB_COSMOS_CONN=$(get_output "$HUB_OUT" hubCosmosConnectionName)

# =========================================================================
# Phase 3 — Spoke
# =========================================================================
if [[ "$START_PHASE" -le 3 ]]; then
  echo ""
  echo "========================================"
  echo "  Phase 3: Spoke Services"
  echo "========================================"
  echo ""

  SPOKE_OUT=$(az deployment sub create \
    --name "aigw-spoke-${TS}" \
    --location "$LOCATION" \
    --template-file "${INFRA_DIR}/spoke.bicep" \
    --parameters \
      location="$LOCATION" \
      environmentName="$ENV_NAME" \
      projectName="$PROJECT_NAME" \
      spokeResourceGroupName="$SPOKE_RG" \
      deploySpokeFoundry="$DEPLOY_SPOKE_FOUNDRY" \
      spokeContainerAppsSubnetId="$SPOKE_CA_SUBNET" \
      spokePrivateEndpointSubnetId="$SPOKE_PE_SUBNET" \
      spokeAgentSubnetId="$SPOKE_AGENT_SUBNET" \
      containerAppsDnsZoneId="$CAE_DNS_ZONE_ID" \
      logAnalyticsCustomerId="$LAW_CUSTOMER_ID" \
      logAnalyticsSharedKey="$LAW_SHARED_KEY" \
      apimGatewayUrl="$APIM_GW_URL" \
      apimSubscriptionKey="$SPOKE_SUB_KEY" \
      appInsightsConnectionString="$APPI_CONN_STR" \
      chatAgentImage="$CHAT_IMAGE" \
      chatAgentPort="$CHAT_PORT" \
      enableAuthSidecar="$ENABLE_AUTH_SIDECAR" \
      entraIdTenantId="$TENANT_ID" \
      blueprintAppId="$BLUEPRINT_APP_ID" \
      agentIdentityAppId="$AGENT_IDENTITY_APP_ID" \
      enableA365Observability="$ENABLE_A365" \
    --query 'properties.outputs' -o json)

  echo "✅ Phase 3 complete"
else
  echo "⏭️  Skipping phase 3 — reading existing spoke outputs..."
  SPOKE_OUT=$(az deployment sub show \
    --name "$(latest_deployment 'aigw-spoke-')" \
    --query 'properties.outputs' -o json 2>/dev/null || echo '{}')
fi

# Extract spoke outputs
CHAT_APP_FQDN=$(get_output "$SPOKE_OUT" sampleAppFqdn)
CAE_DEFAULT_DOMAIN=$(get_output "$SPOKE_OUT" caeDefaultDomain)
CAE_PRIVATE_IP=$(get_output "$SPOKE_OUT" caePrivateIpAddress)
SAMPLE_APP_PRINCIPAL=$(get_output "$SPOKE_OUT" sampleAppPrincipalId)
ACR_LOGIN_SERVER=$(get_output "$SPOKE_OUT" acrLoginServer)
SPOKE_FOUNDRY_ACCOUNT=$(get_output "$SPOKE_OUT" spokeFoundryAccountName)
SPOKE_FOUNDRY_PROJECT=$(get_output "$SPOKE_OUT" spokeFoundryProjectName)
SPOKE_STORAGE_CONN=$(get_output "$SPOKE_OUT" spokeStorageConnectionName)
SPOKE_SEARCH_CONN=$(get_output "$SPOKE_OUT" spokeSearchConnectionName)
SPOKE_COSMOS_CONN=$(get_output "$SPOKE_OUT" spokeCosmosConnectionName)

# =========================================================================
# Phase 4 — Connectivity
# =========================================================================
if [[ "$START_PHASE" -le 4 ]]; then
  echo ""
  echo "========================================"
  echo "  Phase 4: Connectivity"
  echo "========================================"
  echo "  Private endpoints, DNS wildcard, RBAC"
  echo "========================================"
  echo ""

  az deployment sub create \
    --name "aigw-connectivity-${TS}" \
    --location "$LOCATION" \
    --template-file "${INFRA_DIR}/connectivity.bicep" \
    --parameters \
      location="$LOCATION" \
      environmentName="$ENV_NAME" \
      projectName="$PROJECT_NAME" \
      hubResourceGroupName="$HUB_RG" \
      spokeResourceGroupName="$SPOKE_RG" \
      deploySpokeFoundry="$DEPLOY_SPOKE_FOUNDRY" \
      hubPrivateEndpointSubnetId="$HUB_PE_SUBNET" \
      spokePrivateEndpointSubnetId="$SPOKE_PE_SUBNET" \
      cognitiveServicesDnsZoneId="$COG_DNS_ZONE" \
      openAiDnsZoneId="$OAI_DNS_ZONE" \
      aiServicesDnsZoneId="$AIS_DNS_ZONE" \
      storageBlobDnsZoneId="$BLOB_DNS_ZONE" \
      searchDnsZoneId="$SEARCH_DNS_ZONE" \
      cosmosDnsZoneId="$COSMOS_DNS_ZONE" \
      logAnalyticsWorkspaceId="$LAW_ID" \
      apimName="$APIM_NAME" \
      chatAppFqdn="$CHAT_APP_FQDN" \
      caeDefaultDomain="$CAE_DEFAULT_DOMAIN" \
      caePrivateIpAddress="$CAE_PRIVATE_IP" \
      containerAppsDnsZoneName="$CAE_DNS_ZONE_NAME" \
      sampleAppPrincipalId="$SAMPLE_APP_PRINCIPAL" \
    -o none

  echo "✅ Phase 4 complete"
fi

# =========================================================================
# Phase 5 — Capability Hosts + Image Build
# =========================================================================
echo ""
echo "========================================"
echo "  Phase 5: Capability Hosts & Image Build"
echo "========================================"
echo ""

# Export variables for postprovision.sh
export hubResourceGroupName="$HUB_RG"
export spokeResourceGroupName="$SPOKE_RG"
export hubFoundryAccountName="$HUB_FOUNDRY_ACCOUNT"
export hubFoundryProjectName="$HUB_FOUNDRY_PROJECT"
export hubStorageConnectionName="$HUB_STORAGE_CONN"
export hubSearchConnectionName="$HUB_SEARCH_CONN"
export hubCosmosConnectionName="$HUB_COSMOS_CONN"
export spokeFoundryAccountName="$SPOKE_FOUNDRY_ACCOUNT"
export spokeFoundryProjectName="$SPOKE_FOUNDRY_PROJECT"
export spokeStorageConnectionName="$SPOKE_STORAGE_CONN"
export spokeSearchConnectionName="$SPOKE_SEARCH_CONN"
export spokeCosmosConnectionName="$SPOKE_COSMOS_CONN"
export acrLoginServer="$ACR_LOGIN_SERVER"
export apimGatewayUrl="$APIM_GW_URL"

bash "${SCRIPT_DIR}/postprovision.sh"

# =========================================================================
# Done
# =========================================================================
echo ""
echo "========================================"
echo "  Deployment Complete"
echo "========================================"
echo ""
echo "  Hub RG:    ${HUB_RG}"
echo "  Spoke RG:  ${SPOKE_RG}"
echo "  APIM:      ${APIM_GW_URL}"
echo ""
