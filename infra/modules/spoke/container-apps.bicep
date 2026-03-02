// ============================================================================
// Spoke Container Apps & Container Registry
// ============================================================================

@description('Azure region')
param location string

@description('Project name')
param projectName string

@description('Environment name')
param environmentName string

@description('Tags')
param tags object = {}

@description('Container Apps Environment subnet ID')
param containerAppsSubnetId string

@description('Log Analytics customer ID (from hub observability)')
param logAnalyticsCustomerId string

@secure()
@description('Log Analytics shared key (from hub observability)')
param logAnalyticsSharedKey string

@description('APIM Gateway URL for the sample container app')
param apimGatewayUrl string

@secure()
@description('APIM subscription key for calling the model gateway')
param apimSubscriptionKey string = ''

@description('Chat agent container image (set after building and pushing to ACR)')
param chatAgentImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Chat agent container port')
param chatAgentPort int = 80

// ============================================================================
// Variables
// ============================================================================

var resourceSuffix = uniqueString(resourceGroup().id)
var acrName = take('acr${projectName}${resourceSuffix}', 50)

// ============================================================================
// Azure Container Registry
// ============================================================================

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
  }
}

// ============================================================================
// Container Apps Environment
// ============================================================================

resource containerAppsEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${projectName}-${environmentName}'
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: containerAppsSubnetId
      internal: false // Phase 9: switch to true for private-only access
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
  }
}

// ============================================================================
// Sample Container App (placeholder — calls hub APIM)
// ============================================================================

resource sampleApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-sample-${projectName}-${environmentName}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: chatAgentPort
        transport: 'auto'
      }
      secrets: !empty(apimSubscriptionKey)
        ? [
            { name: 'apim-api-key', value: apimSubscriptionKey }
          ]
        : []
      registries: !empty(apimSubscriptionKey)
        ? [
            {
              server: acr.properties.loginServer
              identity: 'system'
            }
          ]
        : []
    }
    template: {
      containers: [
        {
          name: 'chat-agent'
          image: chatAgentImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: concat(
            [
              { name: 'APIM_GATEWAY_URL', value: apimGatewayUrl }
              { name: 'OPENAI_API_BASE', value: '${apimGatewayUrl}/openai' }
              { name: 'OPENAI_DEPLOYMENT_NAME', value: 'gpt-4o' }
            ],
            !empty(apimSubscriptionKey)
              ? [
                  { name: 'APIM_API_KEY', secretRef: 'apim-api-key' }
                ]
              : []
          )
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

// ============================================================================
// RBAC — Container App identity → ACR Pull
// ============================================================================

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, sampleApp.id, '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull
    )
    principalId: sampleApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================

output acrId string = acr.id
output acrLoginServer string = acr.properties.loginServer
output containerAppsEnvId string = containerAppsEnv.id
output containerAppsEnvName string = containerAppsEnv.name
output sampleAppFqdn string = sampleApp.properties.configuration.ingress.fqdn
