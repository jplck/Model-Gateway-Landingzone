// ============================================================================
// Azure AI Foundry — Account, Project, Supporting Resources, Capability Hosts
//
// Deploys the standard capability-hosts pattern:
//   Storage Account, AI Search, Cosmos DB, AI Services Account, Project,
//   Connections, RBAC, Capability Hosts, Private Endpoints, Diagnostics
//
// Reusable for both hub and spoke Foundry deployments (set instanceSuffix).
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

@description('Agent subnet ID (delegated to Microsoft.CognitiveServices/accounts)')
param agentSubnetId string

@description('Log Analytics workspace ID for diagnostic settings')
param logAnalyticsWorkspaceId string

// DNS zone IDs for private endpoints
@description('Private DNS zone ID for Cognitive Services')
param cognitiveServicesDnsZoneId string

@description('Private DNS zone ID for OpenAI')
param openAiDnsZoneId string

@description('Private DNS zone ID for Blob Storage')
param storageBlobDnsZoneId string

@description('Private DNS zone ID for AI Search')
param searchDnsZoneId string

@description('Private DNS zone ID for Cosmos DB')
param cosmosDnsZoneId string

@description('Model deployments to create on this Foundry instance')
param modelDeployments modelDeploymentType[] = [
  {
    name: 'gpt-4o'
    modelName: 'gpt-4o'
    modelVersion: '2024-11-20'
    skuName: 'GlobalStandard'
    capacity: 10
  }
]

// Optional: APIM gateway connection (for spoke Foundry only)
@description('APIM gateway URL for agent gateway connection (leave empty for hub)')
param apimGatewayUrl string = ''

@secure()
@description('APIM subscription key for agent gateway connection')
param apimSubscriptionKey string = ''

// ============================================================================
// Types
// ============================================================================

@export()
type modelDeploymentType = {
  @description('Deployment name')
  name: string

  @description('Model name (e.g., gpt-4o)')
  modelName: string

  @description('Model version')
  modelVersion: string

  @description('SKU name (e.g., GlobalStandard, Standard)')
  skuName: string

  @description('Capacity in TPM units')
  capacity: int
}

// ============================================================================
// Variables
// ============================================================================

var resourceSuffix = uniqueString(resourceGroup().id)
var baseName = '${projectName}-${instanceSuffix}-${environmentName}'
var storageAccountName = take('st${projectName}${instanceSuffix}${resourceSuffix}', 24)
var searchServiceName = 'srch-${baseName}-${take(resourceSuffix, 6)}'
var cosmosAccountName = 'cosmos-${baseName}-${take(resourceSuffix, 6)}'
var aiServicesName = 'ais-${baseName}-${take(resourceSuffix, 6)}'
var foundryProjectName = 'proj-${baseName}-${take(resourceSuffix, 6)}'

// ============================================================================
// Storage Account (file storage for agents)
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

// ============================================================================
// AI Search Service (vector storage)
// ============================================================================

resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchServiceName
  location: location
  tags: tags
  sku: { name: 'basic' }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
  }
}

// ============================================================================
// Cosmos DB — Serverless (thread / message storage)
// ============================================================================

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    capabilities: [
      { name: 'EnableServerless' }
    ]
    locations: [
      { locationName: location, failoverPriority: 0, isZoneRedundant: false }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
  }
}

// ============================================================================
// AI Services Account (Foundry Account)
// ============================================================================

resource aiServicesAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: aiServicesName
  location: location
  tags: tags
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: aiServicesName
    publicNetworkAccess: 'Enabled' // Phase 9: switch to 'Disabled'
    networkAcls: {
      defaultAction: 'Allow' // Phase 9: switch to 'Deny'
    }
    disableLocalAuth: false
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: agentSubnetId
      }
    ]
  }
}

// ============================================================================
// Model Deployments
// ============================================================================

@batchSize(1)
resource deployments 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = [
  for deployment in modelDeployments: {
    parent: aiServicesAccount
    name: deployment.name
    sku: {
      name: deployment.skuName
      capacity: deployment.capacity
    }
    properties: {
      model: {
        format: 'OpenAI'
        name: deployment.modelName
        version: deployment.modelVersion
      }
    }
  }
]

// ============================================================================
// AI Foundry Project
// ============================================================================

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: aiServicesAccount
  name: foundryProjectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: 'AI Foundry project for ${instanceSuffix}'
    displayName: foundryProjectName
  }
}

// ============================================================================
// Connections on the Foundry Account
// ============================================================================

resource storageConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  parent: aiServicesAccount
  name: '${storageAccountName}-connection'
  properties: {
    category: 'AzureBlob'
    target: storageAccount.properties.primaryEndpoints.blob
    authType: 'AAD'
    metadata: {
      ResourceId: storageAccount.id
    }
  }
}

resource searchConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  parent: aiServicesAccount
  name: '${searchServiceName}-connection'
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${searchService.name}.search.windows.net'
    authType: 'AAD'
    metadata: {
      ResourceId: searchService.id
    }
  }
}

resource cosmosConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  parent: aiServicesAccount
  name: '${cosmosAccountName}-connection'
  properties: {
    category: 'CosmosDB'
    target: cosmosAccount.properties.documentEndpoint
    authType: 'AAD'
    metadata: {
      ResourceId: cosmosAccount.id
    }
  }
}

// ============================================================================
// RBAC — AI Services identity needs access to backing resources
// ============================================================================

// Storage Blob Data Contributor
resource storageBlobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, aiServicesAccount.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
    principalId: aiServicesAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Search Index Data Contributor
resource searchIndexDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, aiServicesAccount.id, '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
    )
    principalId: aiServicesAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Search Service Contributor
resource searchServiceContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, aiServicesAccount.id, '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
    )
    principalId: aiServicesAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Cosmos DB Built-in Data Contributor (data-plane role)
resource cosmosDataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, aiServicesAccount.id, '00000000-0000-0000-0000-000000000002')
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    principalId: aiServicesAccount.identity.principalId
    scope: cosmosAccount.id
  }
}

// ============================================================================
// Capability Hosts (Account-level + Project-level)
//
// These depend on RBAC assignments above. The implicit dependency through
// dependsOn provides the ~60-second propagation window.
// ============================================================================

resource accountCapabilityHost 'Microsoft.CognitiveServices/accounts/capabilityHosts@2025-04-01-preview' = {
  parent: aiServicesAccount
  name: 'default'
  properties: {
    capabilityHostKind: 'Agents'
    vectorStoreConnections: [searchConnection.name]
    storageConnections: [storageConnection.name]
    threadStorageConnections: [cosmosConnection.name]
  }
  dependsOn: [
    storageBlobDataContributor
    searchIndexDataContributor
    searchServiceContributor
    cosmosDataContributor
  ]
}

resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: foundryProject
  name: 'default'
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
  }
  dependsOn: [accountCapabilityHost]
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

// ============================================================================
// APIM Gateway Connection (spoke only — when apimGatewayUrl is provided)
// ============================================================================

resource apimGatewayConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' =
  if (!empty(apimGatewayUrl)) {
    parent: aiServicesAccount
    name: 'apim-gateway'
    properties: {
      category: 'ApiManagement'
      target: apimGatewayUrl
      authType: 'ApiKey'
      credentials: {
        key: apimSubscriptionKey
      }
    }
  }

// ============================================================================
// Outputs
// ============================================================================

output foundryAccountId string = aiServicesAccount.id
output foundryAccountName string = aiServicesAccount.name
output foundryEndpoint string = aiServicesAccount.properties.endpoint
output foundryProjectId string = foundryProject.id
output foundryProjectName string = foundryProject.name
output foundryPrincipalId string = aiServicesAccount.identity.principalId
