// ============================================================================
// Container App → Spoke Foundry RBAC
//
// Grants the container app's managed identity the Azure AI Developer role
// on the spoke Foundry AI Services account, enabling Agent SDK operations.
// ============================================================================

@description('Name of the AI Services (Foundry) account')
param foundryAccountName string

@description('Principal ID of the container app managed identity')
param principalId string

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: foundryAccountName
}

// Azure AI Developer — 64702f94-c441-49e6-a78b-ef80e0188fee
// Allows creating/managing agents, threads, running inference via the project
resource aiDeveloperRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundryAccount.id, principalId, '64702f94-c441-49e6-a78b-ef80e0188fee')
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '64702f94-c441-49e6-a78b-ef80e0188fee' // Azure AI Developer
    )
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// Azure AI User — 53ca6127-db72-4b80-b1b0-d745d6d5456d
// Required for agent write data actions (agents/write, threads, runs)
resource aiUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundryAccount.id, principalId, '53ca6127-db72-4b80-b1b0-d745d6d5456d')
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '53ca6127-db72-4b80-b1b0-d745d6d5456d' // Azure AI User
    )
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
