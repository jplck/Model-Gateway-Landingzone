// ============================================================================
// Helper: Extract private IP from a Private Endpoint NIC
// ============================================================================
// Deployed as a nested module so that the NIC name (a runtime value from the
// parent PE) is received as an ordinary string parameter, avoiding BCP307.

@description('Name of the NIC to look up')
param nicName string

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' existing = {
  name: nicName
}

output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
