// ============================================================================
// Phase 2 — Hub Services
//
// Deploys: Observability, Foundry core (account + backing resources), APIM.
//
// Depends on: networking.bicep (Phase 1) for subnet IDs and DNS zone IDs.
// The Foundry account's networkInjections begins async provisioning here.
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

@description('APIM publisher email')
param publisherEmail string = 'admin@contoso.com'

@description('APIM publisher name')
param publisherName string = 'AI Gateway Team'

@description('Hub agent subnet ID (from networking phase)')
param hubAgentSubnetId string

@description('Hub APIM subnet ID (from networking phase)')
param hubApimSubnetId string

@description('Model deployments for the hub Foundry')
param hubModelDeployments array = [
  {
    name: 'gpt-4.1'
    modelName: 'gpt-4.1'
    modelVersion: '2025-04-14'
    skuName: 'GlobalStandard'
    capacity: 10
  }
]

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
// Existing Resource Group
// ============================================================================

resource hubRg 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: hubResourceGroupName
}

// ============================================================================
// Observability
// ============================================================================

module hubObservability 'modules/hub/observability.bicep' = {
  scope: hubRg
  name: 'hub-observability'
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: defaultTags
  }
}

// ============================================================================
// Hub Foundry (Core — no private endpoints)
// ============================================================================

module hubFoundry 'modules/hub/foundry-core.bicep' = {
  scope: hubRg
  name: 'hub-foundry-core'
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: defaultTags
    instanceSuffix: 'hub'
    agentSubnetId: hubAgentSubnetId
    modelDeployments: hubModelDeployments
    appInsightsConnectionString: hubObservability.outputs.appInsightsConnectionString
  }
}

// ============================================================================
// API Management (Model Gateway)
// ============================================================================

module hubApim 'modules/hub/apim.bicep' = {
  scope: hubRg
  name: 'hub-apim'
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: defaultTags
    publisherEmail: publisherEmail
    publisherName: publisherName
    logAnalyticsWorkspaceId: hubObservability.outputs.logAnalyticsWorkspaceId
    appInsightsId: hubObservability.outputs.appInsightsId
    appInsightsInstrumentationKey: hubObservability.outputs.appInsightsInstrumentationKey
    foundryEndpoint: hubFoundry.outputs.foundryEndpoint
    foundryAccountName: hubFoundry.outputs.foundryAccountName
    apimSubnetId: hubApimSubnetId
  }
}

// ============================================================================
// Outputs
// ============================================================================

// Observability
output logAnalyticsWorkspaceId string = hubObservability.outputs.logAnalyticsWorkspaceId
output logAnalyticsCustomerId string = hubObservability.outputs.logAnalyticsCustomerId
#disable-next-line outputs-should-not-contain-secrets
output logAnalyticsSharedKey string = hubObservability.outputs.logAnalyticsSharedKey
output appInsightsConnectionString string = hubObservability.outputs.appInsightsConnectionString

// Foundry
output hubFoundryAccountName string = hubFoundry.outputs.foundryAccountName
output hubFoundryProjectName string = hubFoundry.outputs.foundryProjectName
output hubFoundryEndpoint string = hubFoundry.outputs.foundryEndpoint
output hubFoundryPrincipalId string = hubFoundry.outputs.foundryPrincipalId
output hubProjectPrincipalId string = hubFoundry.outputs.projectPrincipalId
output hubProjectEndpoint string = hubFoundry.outputs.projectEndpoint
output hubStorageConnectionName string = hubFoundry.outputs.storageConnectionName
output hubSearchConnectionName string = hubFoundry.outputs.searchConnectionName
output hubCosmosConnectionName string = hubFoundry.outputs.cosmosConnectionName
output hubStorageAccountName string = hubFoundry.outputs.storageAccountName
output hubSearchServiceName string = hubFoundry.outputs.searchServiceName
output hubCosmosAccountName string = hubFoundry.outputs.cosmosAccountName

// APIM
output apimName string = hubApim.outputs.apimName
output apimGatewayUrl string = hubApim.outputs.apimGatewayUrl
output apimPrincipalId string = hubApim.outputs.apimPrincipalId
#disable-next-line outputs-should-not-contain-secrets
output spokeSubscriptionKey string = hubApim.outputs.spokeSubscriptionKey
