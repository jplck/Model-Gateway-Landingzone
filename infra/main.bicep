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

@description('Chat agent container image (set via CHAT_AGENT_IMAGE env var after building)')
param chatAgentImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Chat agent container port')
param chatAgentPort int = 80

@description('Enable the Agent ID auth sidecar on the container app')
param enableAuthSidecar bool = false

@description('Entra tenant ID')
param entraIdTenantId string = ''

@description('Agent Identity Blueprint app (client) ID')
param blueprintAppId string = ''

@description('Agent Identity app (client) ID')
param agentIdentityAppId string = ''

@description('Enable A365 observability telemetry exporter (requires auth sidecar)')
param enableA365Observability bool = false

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

// Compute the ACR name deterministically (must match container-apps.bicep logic)
// container-apps.bicep uses: take('acr${projectName}${uniqueString(resourceGroup().id)}', 50)
var spokeAcrName = take('acr${projectName}${uniqueString(spokeRg.id)}', 50)

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
    location: location
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
    aiServicesDnsZoneId: hubDns.outputs.aiServicesDnsZoneId
    storageBlobDnsZoneId: hubDns.outputs.storageBlobDnsZoneId
    searchDnsZoneId: hubDns.outputs.searchDnsZoneId
    cosmosDnsZoneId: hubDns.outputs.cosmosDnsZoneId
    modelDeployments: hubModelDeployments
    appInsightsConnectionString: hubObservability.outputs.appInsightsConnectionString
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
    apimSubnetId: hubNetworking.outputs.apimSubnetId
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

// Link spoke VNet to Container Apps private DNS zone
module spokeContainerAppsDnsLink 'modules/dns-zone-link.bicep' = {
  scope: hubRg
  params: {
    dnsZoneName: hubDns.outputs.containerAppsDnsZoneName
    vnetId: spokeNetworking.outputs.vnetId
    linkName: 'link-spoke-vnet'
    tags: tags
  }
}

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
    apimSubscriptionKey: hubApim.outputs.spokeSubscriptionKey
    chatAgentImage: chatAgentImage
    chatAgentPort: chatAgentPort
    privateEndpointSubnetId: spokeNetworking.outputs.privateEndpointSubnetId
    containerAppsDnsZoneId: hubDns.outputs.containerAppsDnsZoneId
    aiProjectEndpoint: deploySpokeFoundry ? spokeFoundry.outputs.projectEndpoint : ''
    enableAuthSidecar: enableAuthSidecar
    entraIdTenantId: entraIdTenantId
    blueprintAppId: blueprintAppId
    agentIdentityAppId: agentIdentityAppId
    enableA365Observability: enableA365Observability
  }
}

// Wildcard DNS record for CAE PE (resolves app FQDNs via private DNS)
module caeWildcardDns 'modules/hub/cae-dns-wildcard.bicep' = {
  scope: hubRg
  params: {
    dnsZoneName: hubDns.outputs.containerAppsDnsZoneName
    envPrefix: split(spokeContainerApps.outputs.caeDefaultDomain, '.')[0]
    privateIpAddress: spokeContainerApps.outputs.caePrivateIpAddress
  }
}

// ============================================================================
// Phase 7b — APIM Chat Frontend (exposes spoke app through hub gateway)
// ============================================================================

module apimChatApi 'modules/hub/apim-chat-api.bicep' = {
  scope: hubRg
  params: {
    apimName: hubApim.outputs.apimName
    chatAppFqdn: spokeContainerApps.outputs.sampleAppFqdn
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
    aiServicesDnsZoneId: hubDns.outputs.aiServicesDnsZoneId
    storageBlobDnsZoneId: hubDns.outputs.storageBlobDnsZoneId
    searchDnsZoneId: hubDns.outputs.searchDnsZoneId
    cosmosDnsZoneId: hubDns.outputs.cosmosDnsZoneId
    modelDeployments: [] // Spoke uses hub models via APIM gateway
    apimGatewayUrl: hubApim.outputs.apimGatewayUrl
    apimSubscriptionKey: hubApim.outputs.spokeSubscriptionKey
    appInsightsConnectionString: hubObservability.outputs.appInsightsConnectionString
    acrLoginServer: '${spokeAcrName}.azurecr.io'
    acrResourceId: '${spokeRg.id}/providers/Microsoft.ContainerRegistry/registries/${spokeAcrName}'
  }
}

// ============================================================================
// Phase 8b — Container App → Spoke Foundry RBAC (Agent SDK access)
// ============================================================================

// Azure AI Developer role on the spoke Foundry account (enables agent CRUD)
module containerAppFoundryRole 'modules/spoke/foundry-role.bicep' = if (deploySpokeFoundry) {
  scope: spokeRg
  params: {
    foundryAccountName: deploySpokeFoundry ? spokeFoundry.outputs.foundryAccountName : ''
    principalId: spokeContainerApps.outputs.sampleAppPrincipalId
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
output chatFrontendUrl string = apimChatApi.outputs.chatFrontendUrl
output spokeProjectEndpoint string = deploySpokeFoundry ? spokeFoundry.outputs.projectEndpoint : ''
output containerAppMiPrincipalId string = spokeContainerApps.outputs.sampleAppPrincipalId
output spokeStorageAccountName string = spokeContainerApps.outputs.spokeStorageAccountName
output spokeStorageBlobEndpoint string = spokeContainerApps.outputs.spokeStorageBlobEndpoint
