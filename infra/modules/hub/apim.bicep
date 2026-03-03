// ============================================================================
// Hub API Management (Model Gateway)
//
// Deploys APIM with:
//   - Managed identity for backend auth to Foundry
//   - OpenAI-compatible API with chat/completions, completions, embeddings
//   - Policies: managed-identity auth, rate limiting, logging
//   - Product + subscription for spoke consumers
//   - App Insights logger + diagnostics
// ============================================================================

@description('Azure region')
param location string

@description('Project name')
param projectName string

@description('Environment name')
param environmentName string

@description('Tags')
param tags object = {}

@description('APIM publisher email')
param publisherEmail string = 'admin@contoso.com'

@description('APIM publisher name')
param publisherName string = 'AI Gateway Team'

@description('APIM SKU (StandardV2 required for Agent Service gateway, Premium for full VNet isolation)')
@allowed(['BasicV2', 'StandardV2'])
param skuName string = 'StandardV2'

@description('Log Analytics workspace ID')
param logAnalyticsWorkspaceId string

@description('Application Insights resource ID')
param appInsightsId string

@description('Application Insights instrumentation key')
param appInsightsInstrumentationKey string

@description('Foundry endpoint URL (used as backend service URL)')
param foundryEndpoint string

@description('Foundry account name (for RBAC reference)')
param foundryAccountName string

@description('Subnet ID for APIM outbound VNet integration (delegated to Microsoft.Web/serverFarms)')
param apimSubnetId string = ''

// ============================================================================
// Variables
// ============================================================================

var resourceSuffix = uniqueString(resourceGroup().id)
var apimName = 'apim-${projectName}-${environmentName}-${take(resourceSuffix, 6)}'

// ============================================================================
// API Management Service
// ============================================================================

resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: !empty(apimSubnetId) ? 'External' : 'None'
    virtualNetworkConfiguration: !empty(apimSubnetId) ? {
      subnetResourceId: apimSubnetId
    } : null
  }
}

// ============================================================================
// RBAC — APIM managed identity → Cognitive Services User on Foundry
// ============================================================================

resource existingFoundryAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: foundryAccountName
}

resource cognitiveServicesUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(existingFoundryAccount.id, apim.id, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  scope: existingFoundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User
    )
    principalId: apim.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Reader on Foundry account — required for ARM-based deployment discovery
resource armReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(existingFoundryAccount.id, apim.id, 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  scope: existingFoundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
    )
    principalId: apim.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// App Insights Logger
// ============================================================================

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2024-06-01-preview' = {
  parent: apim
  name: 'appinsights-logger'
  properties: {
    loggerType: 'applicationInsights'
    resourceId: appInsightsId
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
  }
}

// ============================================================================
// Platform Diagnostic Settings → Log Analytics
// ============================================================================

resource apimDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${apimName}'
  scope: apim
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

// ============================================================================
// Backend — Foundry Endpoint
// ============================================================================

resource foundryBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: apim
  name: 'foundry-backend'
  properties: {
    title: 'Hub Foundry Backend'
    description: 'Primary Azure AI Foundry model endpoint'
    url: '${foundryEndpoint}openai'
    protocol: 'http'
  }
}

// ============================================================================
// API — OpenAI-compatible inference
// ============================================================================

resource openaiApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: 'openai-api'
  properties: {
    displayName: 'OpenAI API'
    description: 'OpenAI-compatible model inference API proxied through AI Gateway'
    path: 'openai'
    protocols: ['https']
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
    serviceUrl: '${foundryEndpoint}openai'
  }
}

// --- Chat Completions ---
resource chatCompletionsOp 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: openaiApi
  name: 'chat-completions'
  properties: {
    displayName: 'Chat Completions'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/chat/completions'
    templateParameters: [
      { name: 'deployment-id', required: true, type: 'string' }
    ]
  }
}

// --- Completions ---
resource completionsOp 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: openaiApi
  name: 'completions'
  properties: {
    displayName: 'Completions'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/completions'
    templateParameters: [
      { name: 'deployment-id', required: true, type: 'string' }
    ]
  }
}

// --- Embeddings ---
resource embeddingsOp 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: openaiApi
  name: 'embeddings'
  properties: {
    displayName: 'Embeddings'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/embeddings'
    templateParameters: [
      { name: 'deployment-id', required: true, type: 'string' }
    ]
  }
}

// ARM management base URL for deployment discovery (cloud-agnostic)
var armBaseUrl = environment().resourceManager
var armFoundryUrl = '${armBaseUrl}${existingFoundryAccount.id}'

// --- List Deployments (for Agent Service dynamic model discovery) ---
resource listDeploymentsOp 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: openaiApi
  name: 'list-deployments'
  properties: {
    displayName: 'List Deployments'
    method: 'GET'
    urlTemplate: '/deployments'
  }
}

resource listDeploymentsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: listDeploymentsOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><authentication-managed-identity resource="${armBaseUrl}" /><rewrite-uri template="/deployments?api-version=2023-05-01" copy-unmatched-params="false" /><set-backend-service base-url="${armFoundryUrl}" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
}

// --- Get Deployment (for Agent Service dynamic model discovery) ---
resource getDeploymentOp 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: openaiApi
  name: 'get-deployment'
  properties: {
    displayName: 'Get Deployment'
    method: 'GET'
    urlTemplate: '/deployments/{deployment-id}'
    templateParameters: [
      { name: 'deployment-id', required: true, type: 'string' }
    ]
  }
}

resource getDeploymentPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: getDeploymentOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><authentication-managed-identity resource="${armBaseUrl}" /><rewrite-uri template="/deployments/{deployment-id}?api-version=2023-05-01" copy-unmatched-params="false" /><set-backend-service base-url="${armFoundryUrl}" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
}

// ============================================================================
// API-level Policy
// ============================================================================

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = {
  parent: openaiApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('policies/openai-api-policy.xml')
  }
}

// ============================================================================
// APIM Diagnostics (request/response logging → App Insights)
// ============================================================================

resource apiDiagnostics 'Microsoft.ApiManagement/service/diagnostics@2024-06-01-preview' = {
  parent: apim
  name: 'applicationinsights'
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
    sampling: {
      percentage: 100
      samplingType: 'fixed'
    }
    frontend: {
      request: { headers: [], body: { bytes: 0 } }
      response: { headers: [], body: { bytes: 0 } }
    }
    backend: {
      request: { headers: [], body: { bytes: 0 } }
      response: { headers: [], body: { bytes: 0 } }
    }
  }
}

// ============================================================================
// Product & Subscription
// ============================================================================

resource gatewayProduct 'Microsoft.ApiManagement/service/products@2024-06-01-preview' = {
  parent: apim
  name: 'model-gateway'
  properties: {
    displayName: 'Model Gateway'
    description: 'Access to AI model endpoints through the gateway'
    state: 'published'
    subscriptionRequired: true
    approvalRequired: false
  }
}

resource productApiLink 'Microsoft.ApiManagement/service/products/apis@2024-06-01-preview' = {
  parent: gatewayProduct
  name: openaiApi.name
}

resource spokeSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-06-01-preview' = {
  parent: apim
  name: 'spoke-subscription'
  properties: {
    displayName: 'Spoke Consumer Subscription'
    scope: gatewayProduct.id
    state: 'active'
    allowTracing: true
  }
}

// ============================================================================
// Outputs
// ============================================================================

output apimId string = apim.id
output apimName string = apim.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output apimPrincipalId string = apim.identity.principalId

#disable-next-line outputs-should-not-contain-secrets
output spokeSubscriptionKey string = spokeSubscription.listSecrets().primaryKey
