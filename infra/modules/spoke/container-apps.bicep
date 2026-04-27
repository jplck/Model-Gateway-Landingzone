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
param chatAgentPort int = 8000

@description('Subnet ID for private endpoints (spoke PE subnet)')
param privateEndpointSubnetId string

@description('Private DNS zone ID for Container Apps Environment')
param containerAppsDnsZoneId string

@description('AI Foundry project endpoint for Agent SDK (optional)')
param aiProjectEndpoint string = ''

@description('APIM gateway connection name for Agent SDK model routing')
param gatewayConnectionName string = 'apim-gateway'

@description('Enable the Agent ID auth sidecar container')
param enableAuthSidecar bool = false

@description('Entra tenant ID')
param entraIdTenantId string = ''

@description('Agent Identity Blueprint app (client) ID')
param blueprintAppId string = ''

@description('Agent Identity app (client) ID — the runtime identity created from the blueprint')
param agentIdentityAppId string = ''

@description('Name for the blob container in the spoke storage account')
param storageContainerName string = 'agent-files'

@description('Enable A365 observability telemetry exporter')
param enableA365Observability bool = false

// ============================================================================
// Variables
// ============================================================================

var resourceSuffix = uniqueString(resourceGroup().id)
var acrName = take('acr${projectName}${resourceSuffix}', 50)
var spokeStorageName = take('staigwspoke${resourceSuffix}', 24)
var isAcrImage = contains(chatAgentImage, acr.properties.loginServer)

// ============================================================================
// Storage Account (spoke — for agent file access)
// ============================================================================

resource spokeStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: spokeStorageName
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

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: spokeStorage
  name: 'default'
}

resource agentFilesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: storageContainerName
}

// ============================================================================
// Azure Container Registry
// ============================================================================

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: { name: 'Standard' }
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
      internal: true
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
      // Agent ID auth sidecar — handles token acquisition, validation, and
      // downstream API calls via the Microsoft Entra SDK for AgentID.
      // Runs alongside the chat-agent, reachable at http://localhost:8080.
      // See: https://learn.microsoft.com/en-us/entra/msidweb/agent-id-sdk/quickstart-python
      containers: concat(
        [
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
                { name: 'OPENAI_DEPLOYMENT_NAME', value: 'gpt-4.1' }
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
                : [],
              enableAuthSidecar
                ? [
                    { name: 'AGENTID_SIDECAR_URL', value: 'http://localhost:8080' }
                    { name: 'AGENT_IDENTITY_APP_ID', value: agentIdentityAppId }
                    { name: 'BLUEPRINT_APP_ID', value: blueprintAppId }
                    { name: 'AZURE_TENANT_ID', value: entraIdTenantId }
                    { name: 'STORAGE_ACCOUNT_URL', value: spokeStorage.properties.primaryEndpoints.blob }
                    { name: 'STORAGE_CONTAINER_NAME', value: storageContainerName }
                  ]
                : [],
              enableAuthSidecar && enableA365Observability
                ? [
                    { name: 'ENABLE_A365_OBSERVABILITY_EXPORTER', value: 'true' }
                    { name: 'ENABLE_A365_OBSERVABILITY', value: 'true' }
                  ]
                : []
            )
          }
        ],
        enableAuthSidecar
          ? [
              {
                name: 'auth-sidecar'
                image: 'mcr.microsoft.com/entra-sdk/auth-sidecar:1.0.0-azurelinux3.0-distroless'
                resources: {
                  cpu: json('0.25')
                  memory: '0.5Gi'
                }
                env: [
                  // --- Entra ID settings (Blueprint identity) ---
                  {
                    name: 'AzureAd__Instance'
                    value: '${environment().authentication.loginEndpoint}/'
                  }
                  { name: 'AzureAd__TenantId', value: entraIdTenantId }
                  { name: 'AzureAd__ClientId', value: blueprintAppId }
                  {
                    name: 'AzureAd__ClientCredentials__0__SourceType'
                    value: 'SignedAssertionFromManagedIdentity'
                  }
                  // --- Downstream API: Cognitive Services (via APIM → Azure OpenAI) ---
                  {
                    name: 'DownstreamApis__CognitiveServices__BaseUrl'
                    value: apimGatewayUrl
                  }
                  {
                    name: 'DownstreamApis__CognitiveServices__Scopes__0'
                    value: 'https://cognitiveservices.azure.com/.default'
                  }
                  {
                    name: 'DownstreamApis__CognitiveServices__RequestAppToken'
                    value: 'true'
                  }
                  {
                    name: 'DownstreamApis__CognitiveServices__AcquireTokenOptions__FmiPath'
                    value: agentIdentityAppId
                  }
                  // --- Downstream API: Azure Storage (blob access) ---
                  {
                    name: 'DownstreamApis__Storage__BaseUrl'
                    value: spokeStorage.properties.primaryEndpoints.blob
                  }
                  {
                    name: 'DownstreamApis__Storage__Scopes__0'
                    value: 'https://storage.azure.com/.default'
                  }
                  {
                    name: 'DownstreamApis__Storage__RequestAppToken'
                    value: 'true'
                  }
                  {
                    name: 'DownstreamApis__Storage__AcquireTokenOptions__FmiPath'
                    value: agentIdentityAppId
                  }
                  // --- Downstream API: Agent Token (FIC exchange token for introspection) ---
                  {
                    name: 'DownstreamApis__AgentToken__BaseUrl'
                    value: environment().authentication.loginEndpoint
                  }
                  {
                    name: 'DownstreamApis__AgentToken__Scopes__0'
                    value: 'api://AzureADTokenExchange/.default'
                  }
                  {
                    name: 'DownstreamApis__AgentToken__RequestAppToken'
                    value: 'true'
                  }
                ]
              }
            ]
          : []
      )
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
// RBAC — Container App identity → Storage Blob Data Contributor (spoke storage)
// ============================================================================

resource storageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(spokeStorage.id, sampleApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: spokeStorage
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
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
output spokeStorageAccountName string = spokeStorage.name
output spokeStorageBlobEndpoint string = spokeStorage.properties.primaryEndpoints.blob
