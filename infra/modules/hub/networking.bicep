// ============================================================================
// Hub Networking — VNet, Subnets, NSGs
// ============================================================================

@description('Azure region for all networking resources')
param location string

@description('Project name used in resource naming')
param projectName string

@description('Environment name (e.g., dev, prod)')
param environmentName string

@description('Hub VNet address space')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('APIM subnet address prefix')
param apimSubnetPrefix string = '10.0.1.0/24'

@description('Private endpoints subnet address prefix')
param privateEndpointSubnetPrefix string = '10.0.2.0/24'

@description('Agent subnet address prefix (delegated to Microsoft.App/environments)')
param agentSubnetPrefix string = '10.0.3.0/24'

@description('Tags applied to all resources')
param tags object = {}

// ============================================================================
// NSGs
// ============================================================================

resource apimNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-apim-${projectName}-${environmentName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTPS-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-APIM-Management'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '3443'
        }
      }
      {
        name: 'Allow-LoadBalancer'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '6390'
        }
      }
    ]
  }
}

resource peNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-pe-${projectName}-${environmentName}'
  location: location
  tags: tags
}

resource agentNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-agent-${projectName}-${environmentName}'
  location: location
  tags: tags
}

// ============================================================================
// Hub VNet
// ============================================================================

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${projectName}-hub-${environmentName}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: 'snet-apim'
        properties: {
          addressPrefix: apimSubnetPrefix
          networkSecurityGroup: { id: apimNsg.id }
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          networkSecurityGroup: { id: peNsg.id }
        }
      }
      {
        name: 'snet-agent'
        properties: {
          addressPrefix: agentSubnetPrefix
          networkSecurityGroup: { id: agentNsg.id }
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
    ]
  }
}

// Use existing references for clean subnet ID outputs
resource apimSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: 'snet-apim'
}

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: 'snet-pe'
}

resource agentSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: 'snet-agent'
}

// ============================================================================
// Outputs
// ============================================================================

output vnetId string = vnet.id
output vnetName string = vnet.name
output apimSubnetId string = apimSubnet.id
output privateEndpointSubnetId string = peSubnet.id
output agentSubnetId string = agentSubnet.id
