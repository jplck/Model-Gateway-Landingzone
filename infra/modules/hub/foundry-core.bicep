// ============================================================================
// Azure AI Foundry — Account, Project, Supporting Resources (Core)
//
// Deploys Foundry account and backing resources:
//   Storage Account, AI Search, Cosmos DB, AI Services Account, Project,
//   Connections, RBAC
//
// Private endpoints and diagnostics are deployed separately via
// foundry-network.bicep to avoid race conditions with networkInjections.
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

@description('Agent subnet ID (delegated to Microsoft.App/environments)')
param agentSubnetId string

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

@description('Application Insights connection string for tracing')
param appInsightsConnectionString string = ''

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
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
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
    publicNetworkAccess: 'disabled'
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
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
    publicNetworkAccess: 'Disabled'
    networkAclBypass: 'AzureServices'
  }
}

// ============================================================================
// AI Services Account (Foundry Account)
// ============================================================================

resource aiServicesAccount 'Microsoft.CognitiveServices/accounts@2025-12-01' = {
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
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    disableLocalAuth: false
    // Inject the agent runtime into the customer VNet so the capability host
    // can reach PE-protected resources (Cosmos DB, Storage, Search) privately.
    networkInjections: !empty(agentSubnetId) ? [
      {
        scenario: 'agent'
        subnetArmId: agentSubnetId
        useMicrosoftManagedNetwork: false
      }
    ] : null
  }
}

// ============================================================================
// Model Deployments
// ============================================================================

@batchSize(1)
resource deployments 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = [
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
// Connections on the Foundry Project (per official Microsoft pattern)
// ============================================================================

resource storageConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: foundryProject
  name: storageAccountName
  properties: {
    category: 'AzureStorageAccount'
    target: storageAccount.properties.primaryEndpoints.blob
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: storageAccount.id
      location: location
    }
  }
}

resource searchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: foundryProject
  name: searchServiceName
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${searchService.name}.search.windows.net'
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchService.id
      location: location
    }
  }
}

resource cosmosConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: foundryProject
  name: cosmosAccountName
  properties: {
    category: 'CosmosDB'
    target: cosmosAccount.properties.documentEndpoint
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosAccount.id
      location: location
    }
  }
}

// ============================================================================
// RBAC — Project identity needs access to backing resources
// (Per official Microsoft pattern: RBAC is assigned to the project's SMI)
// ============================================================================

// Storage Blob Data Contributor (account-level, before capability host)
resource storageBlobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, foundryProject.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Search Index Data Contributor
resource searchIndexDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, foundryProject.id, '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
    )
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Search Service Contributor
resource searchServiceContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, foundryProject.id, '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
    )
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Cosmos DB Operator (control-plane, required BEFORE capability host creates containers)
resource cosmosDbOperator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmosAccount.id, foundryProject.id, '230815da-be43-4aae-9cb4-875f7bd000aa')
  scope: cosmosAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '230815da-be43-4aae-9cb4-875f7bd000aa'
    )
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Cosmos DB data-plane: Built-in Data Contributor for project identity (agent thread R/W)
resource cosmosDataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, foundryProject.id, '00000000-0000-0000-0000-000000000002')
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002' // Built-in Data Contributor
    principalId: foundryProject.identity.principalId
    scope: cosmosAccount.id
  }
}

// Cosmos DB data-plane: Built-in Data Contributor for AI Services account identity
resource cosmosDataContributorAiServices 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, aiServicesAccount.id, '00000000-0000-0000-0000-000000000002')
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002' // Built-in Data Contributor
    principalId: aiServicesAccount.identity.principalId
    scope: cosmosAccount.id
  }
}

// Cognitive Services User — project identity needs this to execute agent actions
resource projectCogServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServicesAccount.id, foundryProject.id, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  scope: aiServicesAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User
    )
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Capability Hosts
//
// IMPORTANT: Capability host creation with VNet injection can take 50+ minutes,
// exceeding the ARM deployment timeout. Caphosts are created by the
// postprovision script (scripts/postprovision.sh) instead of inline Bicep.
// ============================================================================

// ============================================================================
// Application Insights Connection (tracing & telemetry)
// ============================================================================

resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' =
  if (!empty(appInsightsConnectionString)) {
    parent: foundryProject
    name: 'appinsights'
    properties: {
      category: 'AppInsights'
      target: appInsightsConnectionString
      authType: 'ApiKey'
      credentials: {
        key: appInsightsConnectionString
      }
      metadata: {
        ApiType: 'Azure'
      }
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
      target: '${apimGatewayUrl}/openai'
      authType: 'ApiKey'
      credentials: {
        key: apimSubscriptionKey
      }
      metadata: {
        deploymentInPath: 'true'
        inferenceApiVersion: '2024-10-21'
        provider: 'AzureOpenAI'
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
output projectPrincipalId string = foundryProject.identity.principalId
output projectEndpoint string = 'https://${aiServicesAccount.name}.services.ai.azure.com/api/projects/${foundryProject.name}'
output storageConnectionName string = storageConnection.name
output searchConnectionName string = searchConnection.name
output cosmosConnectionName string = cosmosConnection.name
output storageAccountName string = storageAccount.name
output searchServiceName string = searchService.name
output cosmosAccountName string = cosmosAccount.name
