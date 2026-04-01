// ============================================================================
// Phase 4 — Connectivity
//
// Deploys: All Foundry private endpoints + DNS, APIM Chat API,
// CAE DNS wildcard, spoke Foundry RBAC.
//
// By the time this runs, AI Services accounts (with networkInjections)
// have fully provisioned, so private endpoint creation succeeds.
//
// Depends on: spoke.bicep (Phase 3) for CAE outputs, Foundry account names.
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Primary Azure region')
param location string

@description('Environment name (e.g., dev, prod)')
param environmentName string

@description('Project name used in resource naming')
param projectName string = 'aigw'

@description('Hub resource group name')
param hubResourceGroupName string

@description('Spoke resource group name')
param spokeResourceGroupName string

@description('Deploy spoke Foundry private endpoints')
param deploySpokeFoundry bool = false

// Networking inputs (from Phase 1)
@description('Hub PE subnet ID')
param hubPrivateEndpointSubnetId string

@description('Spoke PE subnet ID')
param spokePrivateEndpointSubnetId string

// DNS zone IDs (from Phase 1)
@description('Private DNS zone ID for Cognitive Services')
param cognitiveServicesDnsZoneId string

@description('Private DNS zone ID for OpenAI')
param openAiDnsZoneId string

@description('Private DNS zone ID for AI Services')
param aiServicesDnsZoneId string

@description('Private DNS zone ID for Blob Storage')
param storageBlobDnsZoneId string

@description('Private DNS zone ID for AI Search')
param searchDnsZoneId string

@description('Private DNS zone ID for Cosmos DB')
param cosmosDnsZoneId string

// Hub inputs (from Phase 2)
@description('Log Analytics workspace ID')
param logAnalyticsWorkspaceId string

@description('APIM name')
param apimName string

// Spoke inputs (from Phase 3)
@description('Chat app FQDN for APIM backend')
param chatAppFqdn string

@description('CAE default domain (for wildcard DNS)')
param caeDefaultDomain string

@description('CAE private IP address (for wildcard DNS)')
param caePrivateIpAddress string

@description('Container Apps DNS zone name')
param containerAppsDnsZoneName string

@description('Container app managed identity principal ID')
param sampleAppPrincipalId string

@description('Tags')
param tags object = {}

// ============================================================================
// Variables
// ============================================================================

var defaultTags = union({
  environment: environmentName
  project: projectName
  managedBy: 'bicep'
}, tags)

// ============================================================================
// Existing Resource Groups
// ============================================================================

resource hubRg 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: hubResourceGroupName
}

resource spokeRg 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: spokeResourceGroupName
}

// ============================================================================
// Hub Foundry — Private Endpoints + Diagnostics
// ============================================================================

module hubFoundryNetwork 'modules/hub/foundry-network.bicep' = {
  scope: hubRg
  name: 'hub-foundry-pe'
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: defaultTags
    instanceSuffix: 'hub'
    privateEndpointSubnetId: hubPrivateEndpointSubnetId
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    cognitiveServicesDnsZoneId: cognitiveServicesDnsZoneId
    openAiDnsZoneId: openAiDnsZoneId
    aiServicesDnsZoneId: aiServicesDnsZoneId
    storageBlobDnsZoneId: storageBlobDnsZoneId
    searchDnsZoneId: searchDnsZoneId
    cosmosDnsZoneId: cosmosDnsZoneId
  }
}

// ============================================================================
// Spoke Foundry — Private Endpoints + Diagnostics (conditional)
// ============================================================================

module spokeFoundryNetwork 'modules/hub/foundry-network.bicep' = if (deploySpokeFoundry) {
  scope: spokeRg
  name: 'spoke-foundry-pe'
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: defaultTags
    instanceSuffix: 'spoke'
    privateEndpointSubnetId: spokePrivateEndpointSubnetId
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    cognitiveServicesDnsZoneId: cognitiveServicesDnsZoneId
    openAiDnsZoneId: openAiDnsZoneId
    aiServicesDnsZoneId: aiServicesDnsZoneId
    storageBlobDnsZoneId: storageBlobDnsZoneId
    searchDnsZoneId: searchDnsZoneId
    cosmosDnsZoneId: cosmosDnsZoneId
  }
}

// ============================================================================
// APIM Chat API (exposes spoke app through hub gateway)
// ============================================================================

module apimChatApi 'modules/hub/apim-chat-api.bicep' = {
  scope: hubRg
  name: 'apim-chat-api'
  params: {
    apimName: apimName
    chatAppFqdn: chatAppFqdn
  }
}

// ============================================================================
// CAE Wildcard DNS (resolves app FQDNs via private DNS)
// ============================================================================

module caeWildcardDns 'modules/hub/cae-dns-wildcard.bicep' = {
  scope: hubRg
  name: 'cae-wildcard-dns'
  params: {
    dnsZoneName: containerAppsDnsZoneName
    envPrefix: split(caeDefaultDomain, '.')[0]
    privateIpAddress: caePrivateIpAddress
  }
}

// ============================================================================
// Container App → Spoke Foundry RBAC (conditional)
// ============================================================================

module containerAppFoundryRole 'modules/spoke/foundry-role.bicep' = if (deploySpokeFoundry) {
  scope: spokeRg
  name: 'spoke-foundry-rbac'
  params: {
    foundryAccountName: deploySpokeFoundry ? spokeFoundryAccountName : ''
    principalId: sampleAppPrincipalId
  }
}

// Resolve spoke Foundry account name deterministically (same logic as foundry-core.bicep)
var spokeResourceSuffix = uniqueString(spokeRg.id)
var spokeFoundryAccountName = 'ais-${projectName}-spoke-${environmentName}-${take(spokeResourceSuffix, 6)}'

// ============================================================================
// Outputs
// ============================================================================

output chatFrontendUrl string = apimChatApi.outputs.chatFrontendUrl
