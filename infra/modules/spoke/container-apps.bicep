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

@description('Subnet ID for private endpoints (spoke PE subnet)')
param privateEndpointSubnetId string

@description('Private DNS zone ID for Container Apps Environment')
param containerAppsDnsZoneId string

@description('AI Foundry project endpoint for Agent SDK (optional)')
param aiProjectEndpoint string = ''

@description('APIM gateway connection name for Agent SDK model routing')
param gatewayConnectionName string = 'apim-gateway'

// ============================================================================
// Variables
// ============================================================================

var resourceSuffix = uniqueString(resourceGroup().id)
var acrName = take('acr${projectName}${resourceSuffix}', 50)
var isAcrImage = contains(chatAgentImage, acr.properties.loginServer)

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

resource containerAppsEnv 'Microsoft.App/managedEnvironments@2024-10-02-preview' = {
  name: 'cae-${projectName}-${environmentName}'
  location: location
  tags: tags
  properties: {
    publicNetworkAccess: 'Disabled'
    vnetConfiguration: {
      infrastructureSubnetId: containerAppsSubnetId
      internal: false
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
// Private Endpoint for Container Apps Environment
// ============================================================================

resource caePe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${containerAppsEnv.name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'pe-${containerAppsEnv.name}'
        properties: {
          privateLinkServiceId: containerAppsEnv.id
          groupIds: ['managedEnvironments']
        }
      }
    ]
  }
}



// Resolve the PE NIC IP via a nested module to avoid BCP307
module peNicIp './pe-nic-ip.bicep' = {
  name: 'cae-pe-nic-ip'
  params: {
    nicName: last(split(caePe.properties.networkInterfaces[0].id, '/'))
  }
}

resource caePeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: caePe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'containerapps'
        properties: { privateDnsZoneId: containerAppsDnsZoneId }
      }
    ]
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
      registries: isAcrImage
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
              { name: 'GATEWAY_CONNECTION_NAME', value: gatewayConnectionName }
            ],
            !empty(apimSubscriptionKey)
              ? [
                  { name: 'APIM_API_KEY', secretRef: 'apim-api-key' }
                ]
              : [],
            !empty(aiProjectEndpoint)
              ? [
                  { name: 'AI_PROJECT_ENDPOINT', value: aiProjectEndpoint }
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
output caeDefaultDomain string = containerAppsEnv.properties.defaultDomain
output caePrivateIpAddress string = peNicIp.outputs.privateIpAddress
output sampleAppPrincipalId string = sampleApp.identity.principalId
