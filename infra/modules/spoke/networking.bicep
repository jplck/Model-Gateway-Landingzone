// ============================================================================
// Spoke Networking — VNet, Subnets, NSGs
// ============================================================================

@description('Azure region')
param location string

@description('Project name')
param projectName string

@description('Environment name')
param environmentName string

@description('Tags')
param tags object = {}

@description('Spoke VNet address space')
param vnetAddressPrefix string = '10.1.0.0/16'

@description('Container Apps Environment subnet prefix (minimum /23)')
param containerAppsSubnetPrefix string = '10.1.0.0/23'

@description('Private endpoints subnet prefix')
param privateEndpointSubnetPrefix string = '10.1.2.0/24'

@description('Agent subnet prefix (for optional spoke Foundry)')
param agentSubnetPrefix string = '10.1.3.0/27'

@description('Deploy agent subnet (required when spoke Foundry is enabled)')
param deployAgentSubnet bool = false

// ============================================================================
// NSGs
// ============================================================================

resource containerAppsNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-ca-${projectName}-${environmentName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Deny-Internet-Inbound'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource peNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-spoke-pe-${projectName}-${environmentName}'
  location: location
  tags: tags
}

resource agentNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = if (deployAgentSubnet) {
  name: 'nsg-spoke-agent-${projectName}-${environmentName}'
  location: location
  tags: tags
}

// ============================================================================
// Spoke VNet
// ============================================================================

var baseSubnets = [
  {
    name: 'snet-container-apps'
    properties: {
      addressPrefix: containerAppsSubnetPrefix
      networkSecurityGroup: { id: containerAppsNsg.id }
    }
  }
  {
    name: 'snet-pe'
    properties: {
      addressPrefix: privateEndpointSubnetPrefix
      networkSecurityGroup: { id: peNsg.id }
    }
  }
]

var agentSubnetDef = deployAgentSubnet
  ? [
      {
        name: 'snet-agent'
        properties: {
          addressPrefix: agentSubnetPrefix
          networkSecurityGroup: { id: agentNsg.id }
          delegations: [
            {
              name: 'Microsoft.CognitiveServices.accounts'
              properties: {
                serviceName: 'Microsoft.CognitiveServices/accounts'
              }
            }
          ]
        }
      }
    ]
  : []

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${projectName}-spoke-${environmentName}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: concat(baseSubnets, agentSubnetDef)
  }
}

// ============================================================================
// Subnet references
// ============================================================================

resource containerAppsSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: 'snet-container-apps'
}

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: 'snet-pe'
}

// ============================================================================
// Outputs
// ============================================================================

output vnetId string = vnet.id
output vnetName string = vnet.name
output containerAppsSubnetId string = containerAppsSubnet.id
output privateEndpointSubnetId string = peSubnet.id
output agentSubnetId string = deployAgentSubnet ? '${vnet.id}/subnets/snet-agent' : ''
