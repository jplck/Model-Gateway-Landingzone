// ============================================================================
// Hub Private DNS Zones + VNet Links
// ============================================================================

@description('Hub VNet resource ID to link DNS zones to')
param hubVnetId string

@description('Tags applied to all resources')
param tags object = {}

// ============================================================================
// Private DNS Zones
// ============================================================================

var dnsZoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
  #disable-next-line no-hardcoded-env-urls
  'privatelink.blob.core.windows.net'
  'privatelink.search.windows.net'
  'privatelink.documents.azure.com'
]

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for zone in dnsZoneNames: {
    name: zone
    location: 'global'
    tags: tags
  }
]

resource hubVnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (zone, i) in dnsZoneNames: {
    parent: privateDnsZones[i]
    name: 'link-hub-vnet'
    location: 'global'
    tags: tags
    properties: {
      virtualNetwork: { id: hubVnetId }
      registrationEnabled: false
    }
  }
]

// ============================================================================
// Outputs (by well-known index into dnsZoneNames)
// ============================================================================

output cognitiveServicesDnsZoneId string = privateDnsZones[0].id
output openAiDnsZoneId string = privateDnsZones[1].id
output aiServicesDnsZoneId string = privateDnsZones[2].id
output storageBlobDnsZoneId string = privateDnsZones[3].id
output searchDnsZoneId string = privateDnsZones[4].id
output cosmosDnsZoneId string = privateDnsZones[5].id
