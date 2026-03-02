// ============================================================================
// APIM Chat App API — Exposes the spoke chat agent through the hub gateway
//
// Routes /chat/* requests to the spoke Container App.
// No subscription required (the chat agent calls APIM's OpenAI API
// server-side with its own subscription key).
// ============================================================================

@description('Existing APIM instance name')
param apimName string

@description('Chat agent Container App FQDN (e.g., ca-sample-xxx.region.azurecontainerapps.io)')
param chatAppFqdn string

// ============================================================================
// Reference existing APIM
// ============================================================================

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// ============================================================================
// Backend — Spoke Container App
// ============================================================================

resource chatBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'chat-app-backend'
  properties: {
    protocol: 'http'
    url: 'https://${chatAppFqdn}'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

// ============================================================================
// API — Chat App (path prefix: /chat)
// ============================================================================

resource chatApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'chat-app-api'
  properties: {
    displayName: 'Chat Agent'
    path: 'chat'
    protocols: ['https']
    subscriptionRequired: false
    serviceUrl: 'https://${chatAppFqdn}'
  }
}

// ============================================================================
// Operations
// ============================================================================

resource getFrontend 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: chatApi
  name: 'get-frontend'
  properties: {
    displayName: 'Get Chat Frontend'
    method: 'GET'
    urlTemplate: '/'
  }
}

resource getHealth 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: chatApi
  name: 'get-health'
  properties: {
    displayName: 'Health Check'
    method: 'GET'
    urlTemplate: '/health'
  }
}

resource postChat 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: chatApi
  name: 'post-chat'
  properties: {
    displayName: 'Chat API'
    method: 'POST'
    urlTemplate: '/api/chat'
  }
}

// ============================================================================
// API-level policy — forward to backend, set CORS for browser access
// ============================================================================

resource chatApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: chatApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="chat-app-backend" />
    <cors allow-credentials="false">
      <allowed-origins><origin>*</origin></allowed-origins>
      <allowed-methods><method>GET</method><method>POST</method></allowed-methods>
      <allowed-headers><header>Content-Type</header></allowed-headers>
    </cors>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'''
  }
  dependsOn: [chatBackend]
}

// ============================================================================
// Outputs
// ============================================================================

output chatApiPath string = chatApi.properties.path
output chatFrontendUrl string = '${apim.properties.gatewayUrl}/chat/'
