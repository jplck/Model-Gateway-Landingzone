// ============================================================================
// Azure AI Foundry — Private Endpoints, DNS Zone Groups, Diagnostics
//
// Deployed AFTER foundry-core.bicep to ensure the AI Services account
// (with networkInjections) has fully provisioned before PE creation.
// ============================================================================

@description('Azure region')
param location string

@description('Project name')
param projectName string

@description('Environment name')
param environmentName string

@description('Tags')
param tags object = {}

@description('Instance suffix to differentiate hub/spoke deployments')
param instanceSuffix string = 'hub'

@description('Private endpoint subnet ID')
param privateEndpointSubnetId string

@description('Log Analytics workspace ID for diagnostic settings')
param logAnalyticsWorkspaceId string

// DNS zone IDs for private endpoints
@description('Private DNS zone ID for Cognitive Services')
param cognitiveServicesDnsZoneId string

@description('Private DNS zone ID for OpenAI')
param openAiDnsZoneId string

@description('Private DNS zone ID for AI Services (services.ai.azure.com)')
param aiServicesDnsZoneId string

@description('Private DNS zone ID for Blob Storage')
param storageBlobDnsZoneId string

@description('Private DNS zone ID for AI Search')
param searchDnsZoneId string

@description('Private DNS zone ID for Cosmos DB')
param cosmosDnsZoneId string

// ============================================================================
// Variables — must match foundry-core.bicep naming conventions
// ============================================================================

var resourceSuffix = uniqueString(resourceGroup().id)
var baseName = '${projectName}-${instanceSuffix}-${environmentName}'
var storageAccountName = take('st${projectName}${instanceSuffix}${resourceSuffix}', 24)
var searchServiceName = 'srch-${baseName}-${take(resourceSuffix, 6)}'
var cosmosAccountName = 'cosmos-${baseName}-${take(resourceSuffix, 6)}'
var aiServicesName = 'ais-${baseName}-${take(resourceSuffix, 6)}'

// ============================================================================
// Existing Resource References
// ============================================================================

resource aiServicesAccount 'Microsoft.CognitiveServices/accounts@2025-12-01' existing = {
  name: aiServicesName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: searchServiceName
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: cosmosAccountName
}

// ============================================================================
// Private Endpoints
// ============================================================================

// --- AI Services ---
resource aiServicesPe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${aiServicesName}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'pe-${aiServicesName}'
        properties: {
          privateLinkServiceId: aiServicesAccount.id
          groupIds: ['account']
        }
      }
    ]
  }
}

resource aiServicesPeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: aiServicesPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'cognitiveservices', properties: { privateDnsZoneId: cognitiveServicesDnsZoneId } }
      { name: 'openai', properties: { privateDnsZoneId: openAiDnsZoneId } }
      { name: 'aiservices', properties: { privateDnsZoneId: aiServicesDnsZoneId } }
    ]
  }
}

// --- Storage ---
resource storagePe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${storageAccountName}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'pe-${storageAccountName}'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: ['blob']
        }
      }
    ]
  }
}

resource storagePeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: storagePe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'blob', properties: { privateDnsZoneId: storageBlobDnsZoneId } }
    ]
  }
}

// --- AI Search ---
resource searchPe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${searchServiceName}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'pe-${searchServiceName}'
        properties: {
          privateLinkServiceId: searchService.id
          groupIds: ['searchService']
        }
      }
    ]
  }
}

resource searchPeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: searchPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'search', properties: { privateDnsZoneId: searchDnsZoneId } }
    ]
  }
}

// --- Cosmos DB ---
resource cosmosPe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${cosmosAccountName}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'pe-${cosmosAccountName}'
        properties: {
          privateLinkServiceId: cosmosAccount.id
          groupIds: ['Sql']
        }
      }
    ]
  }
}

resource cosmosPeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: cosmosPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'cosmos', properties: { privateDnsZoneId: cosmosDnsZoneId } }
    ]
  }
}

// ============================================================================
// Diagnostic Settings
// ============================================================================

resource aiServicesDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${aiServicesName}'
  scope: aiServicesAccount
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}
