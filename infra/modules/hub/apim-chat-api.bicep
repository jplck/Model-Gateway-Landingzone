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

resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimName
}

// ============================================================================
// Backend — Spoke Container App
// ============================================================================

resource chatBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
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

resource chatApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
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

resource getFrontend 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: chatApi
  name: 'get-frontend'
  properties: {
    displayName: 'Get Chat Frontend'
    method: 'GET'
    urlTemplate: '/'
  }
}

resource getHealth 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: chatApi
  name: 'get-health'
  properties: {
    displayName: 'Health Check'
    method: 'GET'
    urlTemplate: '/health'
  }
}

resource postChat 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: chatApi
  name: 'post-chat'
  properties: {
    displayName: 'Chat API'
    method: 'POST'
    urlTemplate: '/api/chat'
  }
}

resource getModels 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: chatApi
  name: 'get-models'
  properties: {
    displayName: 'List Discovered Models'
    method: 'GET'
    urlTemplate: '/api/models'
  }
}

resource postAgentChat 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: chatApi
  name: 'post-agent-chat'
  properties: {
    displayName: 'Agent Chat API'
    method: 'POST'
    urlTemplate: '/api/agent/chat'
  }
}

resource getStaticAssets 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: chatApi
  name: 'get-static'
  properties: {
    displayName: 'Static Assets'
    method: 'GET'
    urlTemplate: '/static/*'
  }
}

// ============================================================================
// API-level policy — forward to backend, set CORS for browser access
// ============================================================================

resource chatApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = {
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
