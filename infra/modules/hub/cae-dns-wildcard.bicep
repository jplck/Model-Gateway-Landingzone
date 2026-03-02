// ============================================================================
// Wildcard DNS A record for Container Apps Environment Private Endpoint
//
// When a CAE has publicNetworkAccess=Disabled and a Private Endpoint, the PE
// DNS zone group only creates a record for the environment prefix (e.g.,
// kindcoast-7b175670). Individual app FQDNs (e.g., ca-sample.kindcoast-7b175670)
// need a wildcard record to resolve via the private DNS zone.
// ============================================================================

@description('Private DNS zone name (e.g., privatelink.swedencentral.azurecontainerapps.io)')
param dnsZoneName string

@description('CAE environment prefix — first segment of the defaultDomain (e.g., kindcoast-7b175670)')
param envPrefix string

@description('Private IP address from the CAE Private Endpoint NIC')
param privateIpAddress string

// ============================================================================
// Reference the existing DNS zone (in the hub resource group)
// ============================================================================

resource dnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: dnsZoneName
}

// ============================================================================
// Wildcard A record — resolves *.envPrefix to the PE private IP
// ============================================================================

resource wildcardRecord 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: dnsZone
  name: '*.${envPrefix}'
  properties: {
    ttl: 3600
    aRecords: [
      { ipv4Address: privateIpAddress }
    ]
  }
}
