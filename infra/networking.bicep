// ============================================================================
// Phase 1 — Networking
//
// Creates resource groups, hub + spoke VNets, subnets, NSGs, peering,
// private DNS zones, and DNS zone links.
//
// No dependencies on any service resources. Safe to deploy first.
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

@description('Spoke resource group name')
param spokeResourceGroupName string

@description('Deploy agent subnet in spoke (required for spoke Foundry)')
param deploySpokeFoundry bool = false

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
  name: hubResourceGroupName
  location: location
  tags: defaultTags
}

resource spokeRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: spokeResourceGroupName
  location: location
  tags: defaultTags
}

// ============================================================================
// Hub Networking
// ============================================================================

module hubNetworking 'modules/hub/networking.bicep' = {
  scope: hubRg
  name: 'hub-networking'
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: defaultTags
  }
}

// ============================================================================
// Hub DNS Zones
// ============================================================================

module hubDns 'modules/hub/dns.bicep' = {
  scope: hubRg
  name: 'hub-dns'
  params: {
    hubVnetId: hubNetworking.outputs.vnetId
    location: location
    tags: defaultTags
  }
}

// ============================================================================
// Spoke Networking
// ============================================================================

module spokeNetworking 'modules/spoke/networking.bicep' = {
  scope: spokeRg
  name: 'spoke-networking'
  params: {
    location: location
    projectName: projectName
    environmentName: environmentName
    tags: defaultTags
    deployAgentSubnet: deploySpokeFoundry
  }
}

// ============================================================================
// VNet Peering (bidirectional)
// ============================================================================

module spokeToHubPeering 'modules/peering.bicep' = {
  scope: spokeRg
  name: 'peer-spoke-to-hub'
  params: {
    localVnetName: spokeNetworking.outputs.vnetName
    remoteVnetId: hubNetworking.outputs.vnetId
    peeringName: 'peer-spoke-to-hub'
  }
}

module hubToSpokePeering 'modules/peering.bicep' = {
  scope: hubRg
  name: 'peer-hub-to-spoke'
  params: {
    localVnetName: hubNetworking.outputs.vnetName
    remoteVnetId: spokeNetworking.outputs.vnetId
    peeringName: 'peer-hub-to-spoke'
  }
}

// ============================================================================
// DNS Zone Links — spoke VNet → hub DNS zones
// ============================================================================

module spokeDnsLinks 'modules/dns-zone-link.bicep' = [
  for (zoneName, i) in dnsZoneNames: {
    scope: hubRg
    name: 'dns-link-spoke-${i}'
    params: {
      dnsZoneName: zoneName
      vnetId: spokeNetworking.outputs.vnetId
      linkName: 'link-spoke-vnet'
      tags: defaultTags
    }
    dependsOn: [hubDns]
  }
]

// Link spoke VNet to Container Apps private DNS zone
module spokeContainerAppsDnsLink 'modules/dns-zone-link.bicep' = {
  scope: hubRg
  name: 'dns-link-spoke-cae'
  params: {
    dnsZoneName: hubDns.outputs.containerAppsDnsZoneName
    vnetId: spokeNetworking.outputs.vnetId
    linkName: 'link-spoke-vnet'
    tags: defaultTags
  }
}

// ============================================================================
// Outputs
// ============================================================================

output hubResourceGroupName string = hubRg.name
output spokeResourceGroupName string = spokeRg.name

// Hub networking
output hubVnetId string = hubNetworking.outputs.vnetId
output hubVnetName string = hubNetworking.outputs.vnetName
output hubApimSubnetId string = hubNetworking.outputs.apimSubnetId
output hubPrivateEndpointSubnetId string = hubNetworking.outputs.privateEndpointSubnetId
output hubAgentSubnetId string = hubNetworking.outputs.agentSubnetId

// Spoke networking
output spokeVnetId string = spokeNetworking.outputs.vnetId
output spokeVnetName string = spokeNetworking.outputs.vnetName
output spokeContainerAppsSubnetId string = spokeNetworking.outputs.containerAppsSubnetId
output spokePrivateEndpointSubnetId string = spokeNetworking.outputs.privateEndpointSubnetId
output spokeAgentSubnetId string = spokeNetworking.outputs.agentSubnetId

// DNS zones
output cognitiveServicesDnsZoneId string = hubDns.outputs.cognitiveServicesDnsZoneId
output openAiDnsZoneId string = hubDns.outputs.openAiDnsZoneId
output aiServicesDnsZoneId string = hubDns.outputs.aiServicesDnsZoneId
output storageBlobDnsZoneId string = hubDns.outputs.storageBlobDnsZoneId
output searchDnsZoneId string = hubDns.outputs.searchDnsZoneId
output cosmosDnsZoneId string = hubDns.outputs.cosmosDnsZoneId
output containerAppsDnsZoneId string = hubDns.outputs.containerAppsDnsZoneId
output containerAppsDnsZoneName string = hubDns.outputs.containerAppsDnsZoneName
