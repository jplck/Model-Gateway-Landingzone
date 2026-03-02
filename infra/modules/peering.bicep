// ============================================================================
// VNet Peering — generic helper for creating a single peering direction
// ============================================================================

@description('Name of the local VNet (must exist in current resource group)')
param localVnetName string

@description('Resource ID of the remote VNet to peer with')
param remoteVnetId string

@description('Peering name')
param peeringName string

// ============================================================================
// Reference existing local VNet
// ============================================================================

resource localVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: localVnetName
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: localVnet
  name: peeringName
  properties: {
    remoteVirtualNetwork: { id: remoteVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}
