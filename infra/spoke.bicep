// ============================================================================
// Phase 3 — Spoke Services
//
// Deploys: Container Apps Environment (internal), ACR, spoke storage,
// spoke Foundry core (optional).
//
// Depends on: hub.bicep (Phase 2) for APIM URL, subscription key,
//             observability outputs.
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

@description('Spoke resource group name')
param spokeResourceGroupName string

@description('Deploy the spoke Foundry with Agent Service support')
param deploySpokeFoundry bool = false

// Networking inputs (from Phase 1)
@description('Spoke container apps subnet ID')
param spokeContainerAppsSubnetId string

@description('Spoke private endpoint subnet ID')
param spokePrivateEndpointSubnetId string

@description('Spoke agent subnet ID')
param spokeAgentSubnetId string = ''

@description('Container Apps DNS zone ID (from hub)')
param containerAppsDnsZoneId string

// Hub inputs (from Phase 2)
@description('Log Analytics customer ID')
param logAnalyticsCustomerId string

@secure()
@description('Log Analytics shared key')
param logAnalyticsSharedKey string

@description('APIM Gateway URL')
param apimGatewayUrl string

@secure()
@description('APIM spoke subscription key')
param apimSubscriptionKey string

@description('Application Insights connection string')
param appInsightsConnectionString string = ''

// Container app config
@description('Chat agent container image')
param chatAgentImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Chat agent container port')
param chatAgentPort int = 80

@description('Enable the Agent ID auth sidecar')
param enableAuthSidecar bool = false

@description('Entra tenant ID')
param entraIdTenantId string = ''

@description('Agent Identity Blueprint app (client) ID')
param blueprintAppId string = ''

@description('Agent Identity app (client) ID')
param agentIdentityAppId string = ''

@description('Enable A365 observability telemetry exporter')
param enableA365Observability bool = false

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

resource spokeRg 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: spokeResourceGroupName
}

// ACR name must match container-apps.bicep internal logic
var spokeAcrName = take('acr${projectName}${uniqueString(spokeRg.id)}', 50)

// ============================================================================
// Container Apps + ACR + Spoke Storage
// ============================================================================

module spokeContainerApps 'modules/spoke/container-apps.bicep' = {
  scope: spokeRg
  name: 'spoke-container-apps'
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: defaultTags
    containerAppsSubnetId: spokeContainerAppsSubnetId
    logAnalyticsCustomerId: logAnalyticsCustomerId
    logAnalyticsSharedKey: logAnalyticsSharedKey
    apimGatewayUrl: apimGatewayUrl
    apimSubscriptionKey: apimSubscriptionKey
    chatAgentImage: chatAgentImage
    chatAgentPort: chatAgentPort
    privateEndpointSubnetId: spokePrivateEndpointSubnetId
    containerAppsDnsZoneId: containerAppsDnsZoneId
    aiProjectEndpoint: deploySpokeFoundry ? spokeFoundry.outputs.projectEndpoint! : ''
    enableAuthSidecar: enableAuthSidecar
    entraIdTenantId: entraIdTenantId
    blueprintAppId: blueprintAppId
    agentIdentityAppId: agentIdentityAppId
    enableA365Observability: enableA365Observability
  }
}

// ============================================================================
// Spoke Foundry (Conditional — Agent Service)
// ============================================================================

module spokeFoundry 'modules/hub/foundry-core.bicep' = if (deploySpokeFoundry) {
  scope: spokeRg
  name: 'spoke-foundry-core'
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: defaultTags
    instanceSuffix: 'spoke'
    agentSubnetId: spokeAgentSubnetId
    modelDeployments: [] // Spoke uses hub models via APIM gateway
    apimGatewayUrl: apimGatewayUrl
    apimSubscriptionKey: apimSubscriptionKey
    appInsightsConnectionString: appInsightsConnectionString
    acrLoginServer: '${spokeAcrName}.azurecr.io'
    acrResourceId: '${spokeRg.id}/providers/Microsoft.ContainerRegistry/registries/${spokeAcrName}'
  }
}

// ============================================================================
// Outputs
// ============================================================================

// Container Apps
output acrLoginServer string = spokeContainerApps.outputs.acrLoginServer
output containerAppsEnvName string = spokeContainerApps.outputs.containerAppsEnvName
output sampleAppFqdn string = spokeContainerApps.outputs.sampleAppFqdn
output caeDefaultDomain string = spokeContainerApps.outputs.caeDefaultDomain
output caePrivateIpAddress string = spokeContainerApps.outputs.caePrivateIpAddress
output sampleAppPrincipalId string = spokeContainerApps.outputs.sampleAppPrincipalId
output spokeStorageAccountName string = spokeContainerApps.outputs.spokeStorageAccountName
output spokeStorageBlobEndpoint string = spokeContainerApps.outputs.spokeStorageBlobEndpoint

// Spoke Foundry (conditional)
output spokeFoundryAccountName string = deploySpokeFoundry ? spokeFoundry.outputs.foundryAccountName! : ''
output spokeFoundryProjectName string = deploySpokeFoundry ? spokeFoundry.outputs.foundryProjectName! : ''
output spokeProjectEndpoint string = deploySpokeFoundry ? spokeFoundry.outputs.projectEndpoint! : ''
output spokeStorageConnectionName string = deploySpokeFoundry ? spokeFoundry.outputs.storageConnectionName! : ''
output spokeSearchConnectionName string = deploySpokeFoundry ? spokeFoundry.outputs.searchConnectionName! : ''
output spokeCosmosConnectionName string = deploySpokeFoundry ? spokeFoundry.outputs.cosmosConnectionName! : ''
