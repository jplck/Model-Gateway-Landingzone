// ============================================================================
// Model Gateway Landing Zone — Main Orchestrator
//
// Subscription-scoped deployment that creates hub and spoke resource groups
// and deploys all infrastructure modules.
//
// Each phase section can be deployed incrementally. Comment out later phases
// to deploy only the foundation, then uncomment as you progress.
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Primary Azure region for all resources')
param location string

@description('Environment name (e.g., dev, prod)')
param environmentName string

@description('Project name used in resource naming')
param projectName string = 'aigw'

@description('Deploy the spoke Foundry with Agent Service support')
param deploySpokeFoundry bool = false

@description('APIM publisher email')
param publisherEmail string = 'admin@contoso.com'

@description('APIM publisher name')
param publisherName string = 'AI Gateway Team'

@description('Hub resource group name')
param hubResourceGroupName string

@description('Spoke resource group name')
param spokeResourceGroupName string

@description('Model deployments for the hub Foundry')
param hubModelDeployments array = [
  {
    name: 'gpt-4o'
    modelName: 'gpt-4o'
    modelVersion: '2024-11-20'
    skuName: 'GlobalStandard'
    capacity: 10
  }
]

// ============================================================================
// Variables
// ============================================================================

var tags = {
  environment: environmentName
  project: projectName
  managedBy: 'bicep'
}

var hubRgName = hubResourceGroupName
var spokeRgName = spokeResourceGroupName

var dnsZoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
  #disable-next-line no-hardcoded-env-urls
  'privatelink.blob.core.windows.net'
  'privatelink.search.windows.net'
  'privatelink.documents.azure.com'
]

// ============================================================================
// Resource Groups
// ============================================================================

resource hubRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: hubRgName
  location: location
  tags: tags
}

resource spokeRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: spokeRgName
  location: location
  tags: tags
}

// ============================================================================
// Phase 2 — Hub Foundation (Networking + Observability)
// ============================================================================

module hubNetworking 'modules/hub/networking.bicep' = {
  scope: hubRg
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: tags
  }
}

module hubDns 'modules/hub/dns.bicep' = {
  scope: hubRg
  params: {
    hubVnetId: hubNetworking.outputs.vnetId
    tags: tags
  }
}

module hubObservability 'modules/hub/observability.bicep' = {
  scope: hubRg
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: tags
  }
}

// ============================================================================
// Phase 3 — Hub Foundry (First Model Backend)
// ============================================================================

module hubFoundry 'modules/hub/foundry.bicep' = {
  scope: hubRg
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: tags
    instanceSuffix: 'hub'
    privateEndpointSubnetId: hubNetworking.outputs.privateEndpointSubnetId
    agentSubnetId: hubNetworking.outputs.agentSubnetId
    logAnalyticsWorkspaceId: hubObservability.outputs.logAnalyticsWorkspaceId
    cognitiveServicesDnsZoneId: hubDns.outputs.cognitiveServicesDnsZoneId
    openAiDnsZoneId: hubDns.outputs.openAiDnsZoneId
    storageBlobDnsZoneId: hubDns.outputs.storageBlobDnsZoneId
    searchDnsZoneId: hubDns.outputs.searchDnsZoneId
    cosmosDnsZoneId: hubDns.outputs.cosmosDnsZoneId
    modelDeployments: hubModelDeployments
  }
}

// ============================================================================
// Phase 4 — Hub API Management (Model Gateway)
// ============================================================================

module hubApim 'modules/hub/apim.bicep' = {
  scope: hubRg
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: tags
    publisherEmail: publisherEmail
    publisherName: publisherName
    logAnalyticsWorkspaceId: hubObservability.outputs.logAnalyticsWorkspaceId
    appInsightsId: hubObservability.outputs.appInsightsId
    appInsightsInstrumentationKey: hubObservability.outputs.appInsightsInstrumentationKey
    foundryEndpoint: hubFoundry.outputs.foundryEndpoint
    foundryAccountName: hubFoundry.outputs.foundryAccountName
  }
}

// ============================================================================
// Phase 5 — Multi-Backend & Load Balancing
//
// To add additional Foundry backends, deploy another instance of the foundry
// module (optionally in a different subscription) and register it as an
// additional APIM backend. Update the APIM policy XML to use a backend pool
// with round-robin or priority-based routing.
//
// Example:
//   module hubFoundry2 'modules/hub/foundry.bicep' = {
//     scope: hubRg  // or a different RG/subscription
//     params: { instanceSuffix: 'hub2', ... }
//   }
// ============================================================================

// ============================================================================
// Phase 6 — Spoke Networking & Peering
// ============================================================================

module spokeNetworking 'modules/spoke/networking.bicep' = {
  scope: spokeRg
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: tags
    deployAgentSubnet: deploySpokeFoundry
  }
}

// VNet peering — spoke → hub
module spokeToHubPeering 'modules/peering.bicep' = {
  scope: spokeRg
  params: {
    localVnetName: spokeNetworking.outputs.vnetName
    remoteVnetId: hubNetworking.outputs.vnetId
    peeringName: 'peer-spoke-to-hub'
  }
}

// VNet peering — hub → spoke
module hubToSpokePeering 'modules/peering.bicep' = {
  scope: hubRg
  params: {
    localVnetName: hubNetworking.outputs.vnetName
    remoteVnetId: spokeNetworking.outputs.vnetId
    peeringName: 'peer-hub-to-spoke'
  }
}

// Link spoke VNet to hub private DNS zones
module spokeDnsLinks 'modules/dns-zone-link.bicep' = [
  for (zoneName, i) in dnsZoneNames: {
    scope: hubRg
    params: {
      dnsZoneName: zoneName
      vnetId: spokeNetworking.outputs.vnetId
      linkName: 'link-spoke-vnet'
      tags: tags
    }
    dependsOn: [hubDns]
  }
]

// ============================================================================
// Phase 7 — Spoke Container Apps & Registry
// ============================================================================

module spokeContainerApps 'modules/spoke/container-apps.bicep' = {
  scope: spokeRg
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: tags
    containerAppsSubnetId: spokeNetworking.outputs.containerAppsSubnetId
    logAnalyticsCustomerId: hubObservability.outputs.logAnalyticsCustomerId
    logAnalyticsSharedKey: hubObservability.outputs.logAnalyticsSharedKey
    apimGatewayUrl: hubApim.outputs.apimGatewayUrl
  }
}

// ============================================================================
// Phase 8 — Spoke Foundry (Conditional — Agent Service)
// ============================================================================

module spokeFoundry 'modules/hub/foundry.bicep' = if (deploySpokeFoundry) {
  scope: spokeRg
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: tags
    instanceSuffix: 'spoke'
    privateEndpointSubnetId: spokeNetworking.outputs.privateEndpointSubnetId
    agentSubnetId: spokeNetworking.outputs.agentSubnetId
    logAnalyticsWorkspaceId: hubObservability.outputs.logAnalyticsWorkspaceId
    cognitiveServicesDnsZoneId: hubDns.outputs.cognitiveServicesDnsZoneId
    openAiDnsZoneId: hubDns.outputs.openAiDnsZoneId
    storageBlobDnsZoneId: hubDns.outputs.storageBlobDnsZoneId
    searchDnsZoneId: hubDns.outputs.searchDnsZoneId
    cosmosDnsZoneId: hubDns.outputs.cosmosDnsZoneId
    modelDeployments: [] // Spoke uses hub models via APIM gateway
    apimGatewayUrl: hubApim.outputs.apimGatewayUrl
    apimSubscriptionKey: hubApim.outputs.spokeSubscriptionKey
  }
}

// ============================================================================
// Outputs
// ============================================================================

output hubResourceGroupName string = hubRg.name
output spokeResourceGroupName string = spokeRg.name
output apimGatewayUrl string = hubApim.outputs.apimGatewayUrl
output foundryEndpoint string = hubFoundry.outputs.foundryEndpoint
output acrLoginServer string = spokeContainerApps.outputs.acrLoginServer
output sampleAppFqdn string = spokeContainerApps.outputs.sampleAppFqdn
