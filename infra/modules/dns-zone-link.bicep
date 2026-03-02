// ============================================================================
// Private DNS Zone VNet Link — helper for linking a spoke VNet to a hub DNS zone
// ============================================================================

@description('Name of the existing private DNS zone (e.g., privatelink.blob.core.windows.net)')
param dnsZoneName string

@description('Resource ID of the VNet to link')
param vnetId string

@description('Link name (must be unique per DNS zone)')
param linkName string

@description('Tags')
param tags object = {}

// ============================================================================
// Reference existing DNS zone (must be in current resource group)
// ============================================================================

resource dnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: dnsZoneName
}

resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZone
  name: linkName
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}
