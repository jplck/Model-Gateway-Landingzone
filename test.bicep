@secure()
param properties_69a6b8a1db0fe924943ddd58_value string

@secure()
param properties_69a6ba3dc7d45f06f4150994_value string

@secure()
param properties_69a6bb6cdb0fe924943ddeb9_value string

@secure()
param properties_69a6beeddb0fe924943de047_value string

@secure()
param properties_69a6c24bc7d45f06f4150d2f_value string

@secure()
param properties_69a6cb8dc7d45f06f4151182_value string

@secure()
param properties_69a6d007bf32fb130cefdab2_value string

@secure()
param properties_69a6d40edb0fe922547274f8_value string

@secure()
param properties_69a6d63ddb0fe92254727629_value string

@secure()
param properties_69a6d684c7d45f06f4151698_value string

@secure()
param properties_69a6db97c7d45f06f41518d3_value string

@secure()
param properties_69a6e5abc7d45f06f4151f36_value string

@secure()
param properties_69a6e91bbf32fb130cefe7c9_value string

@secure()
param properties_69a6ea39c7d45f06f4152185_value string

@secure()
param properties_69a6ec1fdb0fe92254728689_value string

@secure()
param properties_69a6f037c7d45f06f41525be_value string

@secure()
param properties_69a6f061db0fe922547288cd_value string

@secure()
param properties_69a6f17ac7d45f06f4152662_value string

@secure()
param properties_69a83effdb0fe92a28f4bdd9_value string

@secure()
param properties_69a861a9bf32fb20f427497f_value string

@secure()
param properties_69a86f6d33f8bc24508bd5ae_value string

@secure()
param properties_69a871c4c7d45f12b4b2cddd_value string

@secure()
param properties_69a8746633f8bc24508bd831_value string

@secure()
param properties_69a8749a33f8bc24508bd846_value string

@secure()
param properties_69a87accdb0fe92a28f4dc6a_value string

@secure()
param properties_69a9512833f8bc24508c4147_value string

@secure()
param properties_69a954d5c7d45f12b4b33764_value string

@secure()
param users_1_lastName string
param service_apim_aigw_aigw2_ea4ky5_name string = 'apim-aigw-aigw2-ea4ky5'
param virtualNetworks_vnet_aigw_hub_aigw2_externalid string = '/subscriptions/5c9ecf91-0bc3-472b-a051-059f1c37767c/resourceGroups/rg-aigw2-aigw-hub/providers/Microsoft.Network/virtualNetworks/vnet-aigw-hub-aigw2'
param components_appi_aigw_aigw2_externalid string = '/subscriptions/5c9ecf91-0bc3-472b-a051-059f1c37767c/resourceGroups/rg-aigw2-aigw-hub/providers/Microsoft.Insights/components/appi-aigw-aigw2'

resource service_apim_aigw_aigw2_ea4ky5_name_resource 'Microsoft.ApiManagement/service@2024-06-01-preview' = {
  name: service_apim_aigw_aigw2_ea4ky5_name
  location: 'Sweden Central'
  tags: {
    environment: 'aigw2'
    project: 'aigw'
    managedBy: 'bicep'
  }
  sku: {
    name: 'StandardV2'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: 'admin@contoso.com'
    publisherName: 'AI Gateway Team'
    notificationSenderEmail: 'apimgmt-noreply@mail.windowsazure.com'
    hostnameConfigurations: [
      {
        type: 'Proxy'
        hostName: '${service_apim_aigw_aigw2_ea4ky5_name}.azure-api.net'
        negotiateClientCertificate: false
        defaultSslBinding: true
        certificateSource: 'BuiltIn'
      }
    ]
    virtualNetworkConfiguration: {
      subnetResourceId: '${virtualNetworks_vnet_aigw_hub_aigw2_externalid}/subnets/snet-apim'
    }
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'False'
    }
    virtualNetworkType: 'External'
    natGatewayState: 'Enabled'
    apiVersionConstraint: {}
    publicNetworkAccess: 'Enabled'
    legacyPortalStatus: 'Disabled'
    developerPortalStatus: 'Disabled'
    releaseChannel: 'Default'
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_chat_app_api 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'chat-app-api'
  properties: {
    displayName: 'Chat Agent'
    apiRevision: '1'
    subscriptionRequired: false
    serviceUrl: 'https://ca-sample-aigw-aigw2.kindcoast-7b175670.swedencentral.azurecontainerapps.io'
    path: 'chat'
    protocols: [
      'https'
    ]
    authenticationSettings: {
      oAuth2AuthenticationSettings: []
      openidAuthenticationSettings: []
    }
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    isCurrent: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_openai_api 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'openai-api'
  properties: {
    displayName: 'OpenAI API'
    apiRevision: '1'
    description: 'OpenAI-compatible model inference API proxied through AI Gateway'
    subscriptionRequired: true
    serviceUrl: 'https://ais-aigw-hub-aigw2-ea4ky5.cognitiveservices.azure.com/openai'
    path: 'openai'
    protocols: [
      'https'
    ]
    authenticationSettings: {
      oAuth2AuthenticationSettings: []
      openidAuthenticationSettings: []
    }
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
    isCurrent: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_chat_app_backend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'chat-app-backend'
  properties: {
    url: 'https://ca-sample-aigw-aigw2.kindcoast-7b175670.swedencentral.azurecontainerapps.io'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_foundry_backend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'foundry-backend'
  properties: {
    title: 'Hub Foundry Backend'
    description: 'Primary Azure AI Foundry model endpoint'
    url: 'https://ais-aigw-hub-aigw2-ea4ky5.cognitiveservices.azure.com/openai'
    protocol: 'http'
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_administrators 'Microsoft.ApiManagement/service/groups@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'administrators'
  properties: {
    displayName: 'Administrators'
    description: 'Administrators is a built-in group containing the admin email account provided at the time of service creation. Its membership is managed by the system.'
    type: 'system'
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_developers 'Microsoft.ApiManagement/service/groups@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'developers'
  properties: {
    displayName: 'Developers'
    description: 'Developers is a built-in group. Its membership is managed by the system. Signed-in users fall into this group.'
    type: 'system'
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_guests 'Microsoft.ApiManagement/service/groups@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'guests'
  properties: {
    displayName: 'Guests'
    description: 'Guests is a built-in group. Its membership is managed by the system. Unauthenticated users visiting the developer portal fall into this group.'
    type: 'system'
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_appinsights_logger 'Microsoft.ApiManagement/service/loggers@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'appinsights-logger'
  properties: {
    loggerType: 'applicationInsights'
    credentials: {
      instrumentationKey: '{{Logger-Credentials--69a954d5c7d45f12b4b33765}}'
    }
    isBuffered: true
    resourceId: components_appi_aigw_aigw2_externalid
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_azuremonitor 'Microsoft.ApiManagement/service/loggers@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'azuremonitor'
  properties: {
    loggerType: 'azureMonitor'
    isBuffered: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6b8a1db0fe924943ddd58 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6b8a1db0fe924943ddd58'
  properties: {
    displayName: 'Logger-Credentials--69a6b8a1db0fe924943ddd59'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6ba3dc7d45f06f4150994 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6ba3dc7d45f06f4150994'
  properties: {
    displayName: 'Logger-Credentials--69a6ba3dc7d45f06f4150995'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6bb6cdb0fe924943ddeb9 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6bb6cdb0fe924943ddeb9'
  properties: {
    displayName: 'Logger-Credentials--69a6bb6cdb0fe924943ddeba'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6beeddb0fe924943de047 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6beeddb0fe924943de047'
  properties: {
    displayName: 'Logger-Credentials--69a6beeddb0fe924943de048'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6c24bc7d45f06f4150d2f 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6c24bc7d45f06f4150d2f'
  properties: {
    displayName: 'Logger-Credentials--69a6c24bc7d45f06f4150d30'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6cb8dc7d45f06f4151182 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6cb8dc7d45f06f4151182'
  properties: {
    displayName: 'Logger-Credentials--69a6cb8dc7d45f06f4151183'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6d007bf32fb130cefdab2 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6d007bf32fb130cefdab2'
  properties: {
    displayName: 'Logger-Credentials--69a6d007bf32fb130cefdab3'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6d40edb0fe922547274f8 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6d40edb0fe922547274f8'
  properties: {
    displayName: 'Logger-Credentials--69a6d40edb0fe922547274f9'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6d63ddb0fe92254727629 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6d63ddb0fe92254727629'
  properties: {
    displayName: 'Logger-Credentials--69a6d63ddb0fe9225472762a'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6d684c7d45f06f4151698 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6d684c7d45f06f4151698'
  properties: {
    displayName: 'Logger-Credentials--69a6d684c7d45f06f4151699'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6db97c7d45f06f41518d3 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6db97c7d45f06f41518d3'
  properties: {
    displayName: 'Logger-Credentials--69a6db97c7d45f06f41518d4'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6e5abc7d45f06f4151f36 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6e5abc7d45f06f4151f36'
  properties: {
    displayName: 'Logger-Credentials--69a6e5abc7d45f06f4151f37'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6e91bbf32fb130cefe7c9 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6e91bbf32fb130cefe7c9'
  properties: {
    displayName: 'Logger-Credentials--69a6e91bbf32fb130cefe7ca'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6ea39c7d45f06f4152185 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6ea39c7d45f06f4152185'
  properties: {
    displayName: 'Logger-Credentials--69a6ea39c7d45f06f4152186'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6ec1fdb0fe92254728689 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6ec1fdb0fe92254728689'
  properties: {
    displayName: 'Logger-Credentials--69a6ec1fdb0fe9225472868a'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6f037c7d45f06f41525be 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6f037c7d45f06f41525be'
  properties: {
    displayName: 'Logger-Credentials--69a6f037c7d45f06f41525bf'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6f061db0fe922547288cd 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6f061db0fe922547288cd'
  properties: {
    displayName: 'Logger-Credentials--69a6f061db0fe922547288ce'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a6f17ac7d45f06f4152662 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6f17ac7d45f06f4152662'
  properties: {
    displayName: 'Logger-Credentials--69a6f17ac7d45f06f4152663'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a83effdb0fe92a28f4bdd9 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a83effdb0fe92a28f4bdd9'
  properties: {
    displayName: 'Logger-Credentials--69a83effdb0fe92a28f4bdda'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a861a9bf32fb20f427497f 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a861a9bf32fb20f427497f'
  properties: {
    displayName: 'Logger-Credentials--69a861a9bf32fb20f4274980'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a86f6d33f8bc24508bd5ae 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a86f6d33f8bc24508bd5ae'
  properties: {
    displayName: 'Logger-Credentials--69a86f6d33f8bc24508bd5af'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a871c4c7d45f12b4b2cddd 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a871c4c7d45f12b4b2cddd'
  properties: {
    displayName: 'Logger-Credentials--69a871c4c7d45f12b4b2cdde'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a8746633f8bc24508bd831 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a8746633f8bc24508bd831'
  properties: {
    displayName: 'Logger-Credentials--69a8746633f8bc24508bd832'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a8749a33f8bc24508bd846 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a8749a33f8bc24508bd846'
  properties: {
    displayName: 'Logger-Credentials--69a8749a33f8bc24508bd847'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a87accdb0fe92a28f4dc6a 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a87accdb0fe92a28f4dc6a'
  properties: {
    displayName: 'Logger-Credentials--69a87accdb0fe92a28f4dc6b'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a9512833f8bc24508c4147 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a9512833f8bc24508c4147'
  properties: {
    displayName: 'Logger-Credentials--69a9512833f8bc24508c4148'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_69a954d5c7d45f12b4b33764 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a954d5c7d45f12b4b33764'
  properties: {
    displayName: 'Logger-Credentials--69a954d5c7d45f12b4b33765'
    secret: true
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_AccountClosedPublisher 'Microsoft.ApiManagement/service/notifications@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'AccountClosedPublisher'
}

resource service_apim_aigw_aigw2_ea4ky5_name_BCC 'Microsoft.ApiManagement/service/notifications@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'BCC'
}

resource service_apim_aigw_aigw2_ea4ky5_name_NewApplicationNotificationMessage 'Microsoft.ApiManagement/service/notifications@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'NewApplicationNotificationMessage'
}

resource service_apim_aigw_aigw2_ea4ky5_name_NewIssuePublisherNotificationMessage 'Microsoft.ApiManagement/service/notifications@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'NewIssuePublisherNotificationMessage'
}

resource service_apim_aigw_aigw2_ea4ky5_name_PurchasePublisherNotificationMessage 'Microsoft.ApiManagement/service/notifications@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'PurchasePublisherNotificationMessage'
}

resource service_apim_aigw_aigw2_ea4ky5_name_QuotaLimitApproachingPublisherNotificationMessage 'Microsoft.ApiManagement/service/notifications@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'QuotaLimitApproachingPublisherNotificationMessage'
}

resource service_apim_aigw_aigw2_ea4ky5_name_RequestPublisherNotificationMessage 'Microsoft.ApiManagement/service/notifications@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'RequestPublisherNotificationMessage'
}

resource service_apim_aigw_aigw2_ea4ky5_name_policy 'Microsoft.ApiManagement/service/policies@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'policy'
  properties: {
    value: '<!--\r\n    IMPORTANT:\r\n    - Policy elements can appear only within the <inbound>, <outbound>, <backend> section elements.\r\n    - Only the <forward-request> policy element can appear within the <backend> section element.\r\n    - To apply a policy to the incoming request (before it is forwarded to the backend service), place a corresponding policy element within the <inbound> section element.\r\n    - To apply a policy to the outgoing response (before it is sent back to the caller), place a corresponding policy element within the <outbound> section element.\r\n    - To add a policy position the cursor at the desired insertion point and click on the round button associated with the policy.\r\n    - To remove a policy, delete the corresponding policy statement from the policy document.\r\n    - Policies are applied in the order of their appearance, from the top down.\r\n-->\r\n<policies>\r\n  <inbound></inbound>\r\n  <backend>\r\n    <forward-request />\r\n  </backend>\r\n  <outbound></outbound>\r\n</policies>'
    format: 'xml'
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_default 'Microsoft.ApiManagement/service/portalconfigs@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'default'
  properties: {
    enableBasicAuth: true
    signin: {
      require: false
    }
    signup: {
      termsOfService: {
        requireConsent: false
      }
    }
    delegation: {
      delegateRegistration: false
      delegateSubscription: false
    }
    cors: {
      allowedOrigins: []
    }
    csp: {
      mode: 'disabled'
      reportUri: []
      allowedSources: []
    }
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_model_gateway 'Microsoft.ApiManagement/service/products@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'model-gateway'
  properties: {
    displayName: 'Model Gateway'
    description: 'Access to AI model endpoints through the gateway'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6b8a1db0fe924943ddd58 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6b8a1db0fe924943ddd58'
  properties: {
    displayName: 'Logger-Credentials--69a6b8a1db0fe924943ddd59'
    secret: true
    value: properties_69a6b8a1db0fe924943ddd58_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6ba3dc7d45f06f4150994 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6ba3dc7d45f06f4150994'
  properties: {
    displayName: 'Logger-Credentials--69a6ba3dc7d45f06f4150995'
    secret: true
    value: properties_69a6ba3dc7d45f06f4150994_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6bb6cdb0fe924943ddeb9 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6bb6cdb0fe924943ddeb9'
  properties: {
    displayName: 'Logger-Credentials--69a6bb6cdb0fe924943ddeba'
    secret: true
    value: properties_69a6bb6cdb0fe924943ddeb9_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6beeddb0fe924943de047 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6beeddb0fe924943de047'
  properties: {
    displayName: 'Logger-Credentials--69a6beeddb0fe924943de048'
    secret: true
    value: properties_69a6beeddb0fe924943de047_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6c24bc7d45f06f4150d2f 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6c24bc7d45f06f4150d2f'
  properties: {
    displayName: 'Logger-Credentials--69a6c24bc7d45f06f4150d30'
    secret: true
    value: properties_69a6c24bc7d45f06f4150d2f_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6cb8dc7d45f06f4151182 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6cb8dc7d45f06f4151182'
  properties: {
    displayName: 'Logger-Credentials--69a6cb8dc7d45f06f4151183'
    secret: true
    value: properties_69a6cb8dc7d45f06f4151182_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6d007bf32fb130cefdab2 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6d007bf32fb130cefdab2'
  properties: {
    displayName: 'Logger-Credentials--69a6d007bf32fb130cefdab3'
    secret: true
    value: properties_69a6d007bf32fb130cefdab2_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6d40edb0fe922547274f8 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6d40edb0fe922547274f8'
  properties: {
    displayName: 'Logger-Credentials--69a6d40edb0fe922547274f9'
    secret: true
    value: properties_69a6d40edb0fe922547274f8_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6d63ddb0fe92254727629 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6d63ddb0fe92254727629'
  properties: {
    displayName: 'Logger-Credentials--69a6d63ddb0fe9225472762a'
    secret: true
    value: properties_69a6d63ddb0fe92254727629_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6d684c7d45f06f4151698 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6d684c7d45f06f4151698'
  properties: {
    displayName: 'Logger-Credentials--69a6d684c7d45f06f4151699'
    secret: true
    value: properties_69a6d684c7d45f06f4151698_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6db97c7d45f06f41518d3 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6db97c7d45f06f41518d3'
  properties: {
    displayName: 'Logger-Credentials--69a6db97c7d45f06f41518d4'
    secret: true
    value: properties_69a6db97c7d45f06f41518d3_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6e5abc7d45f06f4151f36 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6e5abc7d45f06f4151f36'
  properties: {
    displayName: 'Logger-Credentials--69a6e5abc7d45f06f4151f37'
    secret: true
    value: properties_69a6e5abc7d45f06f4151f36_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6e91bbf32fb130cefe7c9 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6e91bbf32fb130cefe7c9'
  properties: {
    displayName: 'Logger-Credentials--69a6e91bbf32fb130cefe7ca'
    secret: true
    value: properties_69a6e91bbf32fb130cefe7c9_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6ea39c7d45f06f4152185 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6ea39c7d45f06f4152185'
  properties: {
    displayName: 'Logger-Credentials--69a6ea39c7d45f06f4152186'
    secret: true
    value: properties_69a6ea39c7d45f06f4152185_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6ec1fdb0fe92254728689 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6ec1fdb0fe92254728689'
  properties: {
    displayName: 'Logger-Credentials--69a6ec1fdb0fe9225472868a'
    secret: true
    value: properties_69a6ec1fdb0fe92254728689_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6f037c7d45f06f41525be 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6f037c7d45f06f41525be'
  properties: {
    displayName: 'Logger-Credentials--69a6f037c7d45f06f41525bf'
    secret: true
    value: properties_69a6f037c7d45f06f41525be_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6f061db0fe922547288cd 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6f061db0fe922547288cd'
  properties: {
    displayName: 'Logger-Credentials--69a6f061db0fe922547288ce'
    secret: true
    value: properties_69a6f061db0fe922547288cd_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a6f17ac7d45f06f4152662 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a6f17ac7d45f06f4152662'
  properties: {
    displayName: 'Logger-Credentials--69a6f17ac7d45f06f4152663'
    secret: true
    value: properties_69a6f17ac7d45f06f4152662_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a83effdb0fe92a28f4bdd9 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a83effdb0fe92a28f4bdd9'
  properties: {
    displayName: 'Logger-Credentials--69a83effdb0fe92a28f4bdda'
    secret: true
    value: properties_69a83effdb0fe92a28f4bdd9_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a861a9bf32fb20f427497f 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a861a9bf32fb20f427497f'
  properties: {
    displayName: 'Logger-Credentials--69a861a9bf32fb20f4274980'
    secret: true
    value: properties_69a861a9bf32fb20f427497f_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a86f6d33f8bc24508bd5ae 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a86f6d33f8bc24508bd5ae'
  properties: {
    displayName: 'Logger-Credentials--69a86f6d33f8bc24508bd5af'
    secret: true
    value: properties_69a86f6d33f8bc24508bd5ae_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a871c4c7d45f12b4b2cddd 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a871c4c7d45f12b4b2cddd'
  properties: {
    displayName: 'Logger-Credentials--69a871c4c7d45f12b4b2cdde'
    secret: true
    value: properties_69a871c4c7d45f12b4b2cddd_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a8746633f8bc24508bd831 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a8746633f8bc24508bd831'
  properties: {
    displayName: 'Logger-Credentials--69a8746633f8bc24508bd832'
    secret: true
    value: properties_69a8746633f8bc24508bd831_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a8749a33f8bc24508bd846 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a8749a33f8bc24508bd846'
  properties: {
    displayName: 'Logger-Credentials--69a8749a33f8bc24508bd847'
    secret: true
    value: properties_69a8749a33f8bc24508bd846_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a87accdb0fe92a28f4dc6a 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a87accdb0fe92a28f4dc6a'
  properties: {
    displayName: 'Logger-Credentials--69a87accdb0fe92a28f4dc6b'
    secret: true
    value: properties_69a87accdb0fe92a28f4dc6a_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a9512833f8bc24508c4147 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a9512833f8bc24508c4147'
  properties: {
    displayName: 'Logger-Credentials--69a9512833f8bc24508c4148'
    secret: true
    value: properties_69a9512833f8bc24508c4147_value
  }
}

resource Microsoft_ApiManagement_service_properties_service_apim_aigw_aigw2_ea4ky5_name_69a954d5c7d45f12b4b33764 'Microsoft.ApiManagement/service/properties@2019-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '69a954d5c7d45f12b4b33764'
  properties: {
    displayName: 'Logger-Credentials--69a954d5c7d45f12b4b33765'
    secret: true
    value: properties_69a954d5c7d45f12b4b33764_value
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_master 'Microsoft.ApiManagement/service/subscriptions@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'master'
  properties: {
    scope: '${service_apim_aigw_aigw2_ea4ky5_name_resource.id}/'
    displayName: 'Built-in all-access subscription'
    state: 'active'
    allowTracing: false
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_AccountClosedDeveloper 'Microsoft.ApiManagement/service/templates@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'AccountClosedDeveloper'
  properties: {
    subject: 'Thank you for using the $OrganizationName API!'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          On behalf of $OrganizationName and our customers we thank you for giving us a try. Your $OrganizationName API account is now closed.\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Your $OrganizationName Team</p>\r\n    <a href="$DevPortalUrl">$DevPortalUrl</a>\r\n    <p />\r\n  </body>\r\n</html>'
    title: 'Developer farewell letter'
    description: 'Developers receive this farewell email after they close their account.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_ApplicationApprovedNotificationMessage 'Microsoft.ApiManagement/service/templates@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'ApplicationApprovedNotificationMessage'
  properties: {
    subject: 'Your application $AppName is published in the application gallery'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          We are happy to let you know that your request to publish the $AppName application in the application gallery has been approved. Your application has been published and can be viewed <a href="http://$DevPortalUrl/Applications/Details/$AppId">here</a>.\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Best,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">The $OrganizationName API Team</p>\r\n  </body>\r\n</html>'
    title: 'Application gallery submission approved (deprecated)'
    description: 'Developers who submitted their application for publication in the application gallery on the developer portal receive this email after their submission is approved.'
    parameters: [
      {
        name: 'AppId'
        title: 'Application id'
      }
      {
        name: 'AppName'
        title: 'Application name'
      }
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_ConfirmSignUpIdentityDefault 'Microsoft.ApiManagement/service/templates@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'ConfirmSignUpIdentityDefault'
  properties: {
    subject: 'Please confirm your new $OrganizationName API account'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head>\r\n    <meta charset="UTF-8" />\r\n    <title>Letter</title>\r\n  </head>\r\n  <body>\r\n    <table width="100%">\r\n      <tr>\r\n        <td>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'"></p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you for joining the $OrganizationName API program! We host a growing number of cool APIs and strive to provide an awesome experience for API developers.</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">First order of business is to activate your account and get you going. To that end, please click on the following link:</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            <a id="confirmUrl" href="$ConfirmUrl" style="text-decoration:none">\r\n              <strong>$ConfirmUrl</strong>\r\n            </a>\r\n          </p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">If clicking the link does not work, please copy-and-paste or re-type it into your browser\'s address bar and hit "Enter".</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">$OrganizationName API Team</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            <a href="$DevPortalUrl">$DevPortalUrl</a>\r\n          </p>\r\n        </td>\r\n      </tr>\r\n    </table>\r\n  </body>\r\n</html>'
    title: 'New developer account confirmation'
    description: 'Developers receive this email to confirm their e-mail address after they sign up for a new account.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
      {
        name: 'ConfirmUrl'
        title: 'Developer activation URL'
      }
      {
        name: 'DevPortalHost'
        title: 'Developer portal hostname'
      }
      {
        name: 'ConfirmQuery'
        title: 'Query string part of the activation URL'
      }
    ]
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_EmailChangeIdentityDefault 'Microsoft.ApiManagement/service/templates@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'EmailChangeIdentityDefault'
  properties: {
    subject: 'Please confirm the new email associated with your $OrganizationName API account'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head>\r\n    <meta charset="UTF-8" />\r\n    <title>Letter</title>\r\n  </head>\r\n  <body>\r\n    <table width="100%">\r\n      <tr>\r\n        <td>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'"></p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">You are receiving this email because you made a change to the email address on your $OrganizationName API account.</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Please click on the following link to confirm the change:</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            <a id="confirmUrl" href="$ConfirmUrl" style="text-decoration:none">\r\n              <strong>$ConfirmUrl</strong>\r\n            </a>\r\n          </p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">If clicking the link does not work, please copy-and-paste or re-type it into your browser\'s address bar and hit "Enter".</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">$OrganizationName API Team</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            <a href="$DevPortalUrl">$DevPortalUrl</a>\r\n          </p>\r\n        </td>\r\n      </tr>\r\n    </table>\r\n  </body>\r\n</html>'
    title: 'Email change confirmation'
    description: 'Developers receive this email to confirm a new e-mail address after they change their existing one associated with their account.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
      {
        name: 'ConfirmUrl'
        title: 'Developer confirmation URL'
      }
      {
        name: 'DevPortalHost'
        title: 'Developer portal hostname'
      }
      {
        name: 'ConfirmQuery'
        title: 'Query string part of the confirmation URL'
      }
    ]
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_InviteUserNotificationMessage 'Microsoft.ApiManagement/service/templates@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'InviteUserNotificationMessage'
  properties: {
    subject: 'You are invited to join the $OrganizationName developer network'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          Your account has been created. Please follow the link below to visit the $OrganizationName developer portal and claim it:\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n      <a href="$ConfirmUrl">$ConfirmUrl</a>\r\n    </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Best,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">The $OrganizationName API Team</p>\r\n  </body>\r\n</html>'
    title: 'Invite user'
    description: 'An e-mail invitation to create an account, sent on request by API publishers.'
    parameters: [
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'ConfirmUrl'
        title: 'Confirmation link'
      }
      {
        name: 'DevPortalHost'
        title: 'Developer portal hostname'
      }
      {
        name: 'ConfirmQuery'
        title: 'Query string part of the confirmation link'
      }
    ]
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_NewCommentNotificationMessage 'Microsoft.ApiManagement/service/templates@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'NewCommentNotificationMessage'
  properties: {
    subject: '$IssueName issue has a new comment'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">This is a brief note to let you know that $CommenterFirstName $CommenterLastName made the following comment on the issue $IssueName you created:</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">$CommentText</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          To view the issue on the developer portal click <a href="http://$DevPortalUrl/issues/$IssueId">here</a>.\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Best,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">The $OrganizationName API Team</p>\r\n  </body>\r\n</html>'
    title: 'New comment added to an issue (deprecated)'
    description: 'Developers receive this email when someone comments on the issue they created on the Issues page of the developer portal.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'CommenterFirstName'
        title: 'Commenter first name'
      }
      {
        name: 'CommenterLastName'
        title: 'Commenter last name'
      }
      {
        name: 'IssueId'
        title: 'Issue id'
      }
      {
        name: 'IssueName'
        title: 'Issue name'
      }
      {
        name: 'CommentText'
        title: 'Comment text'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_NewDeveloperNotificationMessage 'Microsoft.ApiManagement/service/templates@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'NewDeveloperNotificationMessage'
  properties: {
    subject: 'Welcome to the $OrganizationName API!'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head>\r\n    <meta charset="UTF-8" />\r\n    <title>Letter</title>\r\n  </head>\r\n  <body>\r\n    <h1 style="color:#000505;font-size:18pt;font-family:\'Segoe UI\'">\r\n          Welcome to <span style="color:#003363">$OrganizationName API!</span></h1>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Your $OrganizationName API program registration is completed and we are thrilled to have you as a customer. Here are a few important bits of information for your reference:</p>\r\n    <table width="100%" style="margin:20px 0">\r\n      <tr>\r\n            #if ($IdentityProvider == "Basic")\r\n            <td width="50%" style="height:40px;vertical-align:top;font-family:\'Segoe UI\';font-size:12pt">\r\n              Please use the following <strong>username</strong> when signing into any of the \${OrganizationName}-hosted developer portals:\r\n            </td><td style="vertical-align:top;font-family:\'Segoe UI\';font-size:12pt"><strong>$DevUsername</strong></td>\r\n            #else\r\n            <td width="50%" style="height:40px;vertical-align:top;font-family:\'Segoe UI\';font-size:12pt">\r\n              Please use the following <strong>$IdentityProvider account</strong> when signing into any of the \${OrganizationName}-hosted developer portals:\r\n            </td><td style="vertical-align:top;font-family:\'Segoe UI\';font-size:12pt"><strong>$DevUsername</strong></td>            \r\n            #end\r\n          </tr>\r\n      <tr>\r\n        <td style="height:40px;vertical-align:top;font-family:\'Segoe UI\';font-size:12pt">\r\n              We will direct all communications to the following <strong>email address</strong>:\r\n            </td>\r\n        <td style="vertical-align:top;font-family:\'Segoe UI\';font-size:12pt">\r\n          <a href="mailto:$DevEmail" style="text-decoration:none">\r\n            <strong>$DevEmail</strong>\r\n          </a>\r\n        </td>\r\n      </tr>\r\n    </table>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Best of luck in your API pursuits!</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">$OrganizationName API Team</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n      <a href="http://$DevPortalUrl">$DevPortalUrl</a>\r\n    </p>\r\n  </body>\r\n</html>'
    title: 'Developer welcome letter'
    description: 'Developers receive this “welcome” email after they confirm their new account.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'DevUsername'
        title: 'Developer user name'
      }
      {
        name: 'DevEmail'
        title: 'Developer email'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
      {
        name: 'IdentityProvider'
        title: 'Identity Provider selected by Organization'
      }
    ]
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_NewIssueNotificationMessage 'Microsoft.ApiManagement/service/templates@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'NewIssueNotificationMessage'
  properties: {
    subject: 'Your request $IssueName was received'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you for contacting us. Our API team will review your issue and get back to you soon.</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          Click this <a href="http://$DevPortalUrl/issues/$IssueId">link</a> to view or edit your request.\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Best,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">The $OrganizationName API Team</p>\r\n  </body>\r\n</html>'
    title: 'New issue received (deprecated)'
    description: 'This email is sent to developers after they create a new topic on the Issues page of the developer portal.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'IssueId'
        title: 'Issue id'
      }
      {
        name: 'IssueName'
        title: 'Issue name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_PasswordResetByAdminNotificationMessage 'Microsoft.ApiManagement/service/templates@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'PasswordResetByAdminNotificationMessage'
  properties: {
    subject: 'Your password was reset'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <table width="100%">\r\n      <tr>\r\n        <td>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'"></p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">The password of your $OrganizationName API account has been reset, per your request.</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n                Your new password is: <strong>$DevPassword</strong></p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Please make sure to change it next time you sign in.</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">$OrganizationName API Team</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            <a href="$DevPortalUrl">$DevPortalUrl</a>\r\n          </p>\r\n        </td>\r\n      </tr>\r\n    </table>\r\n  </body>\r\n</html>'
    title: 'Password reset by publisher notification (Password reset by admin)'
    description: 'Developers receive this email when the publisher resets their password.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'DevPassword'
        title: 'New Developer password'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_PasswordResetIdentityDefault 'Microsoft.ApiManagement/service/templates@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'PasswordResetIdentityDefault'
  properties: {
    subject: 'Your password change request'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head>\r\n    <meta charset="UTF-8" />\r\n    <title>Letter</title>\r\n  </head>\r\n  <body>\r\n    <table width="100%">\r\n      <tr>\r\n        <td>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'"></p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">You are receiving this email because you requested to change the password on your $OrganizationName API account.</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Please click on the link below and follow instructions to create your new password:</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            <a id="resetUrl" href="$ConfirmUrl" style="text-decoration:none">\r\n              <strong>$ConfirmUrl</strong>\r\n            </a>\r\n          </p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">If clicking the link does not work, please copy-and-paste or re-type it into your browser\'s address bar and hit "Enter".</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">$OrganizationName API Team</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            <a href="$DevPortalUrl">$DevPortalUrl</a>\r\n          </p>\r\n        </td>\r\n      </tr>\r\n    </table>\r\n  </body>\r\n</html>'
    title: 'Password change confirmation'
    description: 'Developers receive this email when they request a password change of their account. The purpose of the email is to verify that the account owner made the request and to provide a one-time perishable URL for changing the password.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
      {
        name: 'ConfirmUrl'
        title: 'Developer new password instruction URL'
      }
      {
        name: 'DevPortalHost'
        title: 'Developer portal hostname'
      }
      {
        name: 'ConfirmQuery'
        title: 'Query string part of the instruction URL'
      }
    ]
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_PurchaseDeveloperNotificationMessage 'Microsoft.ApiManagement/service/templates@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'PurchaseDeveloperNotificationMessage'
  properties: {
    subject: 'Your subscription to the $ProdName'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Greetings $DevFirstName $DevLastName!</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          Thank you for subscribing to the <a href="http://$DevPortalUrl/product#product=$ProdId"><strong>$ProdName</strong></a> and welcome to the $OrganizationName developer community. We are delighted to have you as part of the team and are looking forward to the amazing applications you will build using our API!\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Below are a few subscription details for your reference:</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n      <ul>\r\n            #if ($SubStartDate != "")\r\n            <li style="font-size:12pt;font-family:\'Segoe UI\'">Start date: $SubStartDate</li>\r\n            #end\r\n            \r\n            #if ($SubTerm != "")\r\n            <li style="font-size:12pt;font-family:\'Segoe UI\'">Subscription term: $SubTerm</li>\r\n            #end\r\n          </ul>\r\n    </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            Visit the developer <a href="http://$DevPortalUrl/profile">profile area</a> to manage your subscription and subscription keys\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">A couple of pointers to help get you started:</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n      <strong>\r\n        <a href="http://$DevPortalUrl/product#product=$ProdId">Learn about the API</a>\r\n      </strong>\r\n    </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">The API documentation provides all information necessary to make a request and to process a response. Code samples are provided per API operation in a variety of languages. Moreover, an interactive console allows making API calls directly from the developer portal without writing any code.</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Happy hacking,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">The $OrganizationName API Team</p>\r\n    <a style="font-size:12pt;font-family:\'Segoe UI\'" href="http://$DevPortalUrl">$DevPortalUrl</a>\r\n  </body>\r\n</html>'
    title: 'New subscription activated'
    description: 'Developers receive this acknowledgement email after subscribing to a product.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'ProdId'
        title: 'Product ID'
      }
      {
        name: 'ProdName'
        title: 'Product name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'SubStartDate'
        title: 'Subscription start date'
      }
      {
        name: 'SubTerm'
        title: 'Subscription term'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_QuotaLimitApproachingDeveloperNotificationMessage 'Microsoft.ApiManagement/service/templates@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'QuotaLimitApproachingDeveloperNotificationMessage'
  properties: {
    subject: 'You are approaching an API quota limit'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head>\r\n    <style>\r\n          body {font-size:12pt; font-family:"Segoe UI","Segoe WP","Tahoma","Arial","sans-serif";}\r\n          .alert { color: red; }\r\n          .child1 { padding-left: 20px; }\r\n          .child2 { padding-left: 40px; }\r\n          .number { text-align: right; }\r\n          .text { text-align: left; }\r\n          th, td { padding: 4px 10px; min-width: 100px; }\r\n          th { background-color: #DDDDDD;}\r\n        </style>\r\n  </head>\r\n  <body>\r\n    <p>Greetings $DevFirstName $DevLastName!</p>\r\n    <p>\r\n          You are approaching the quota limit on you subscription to the <strong>$ProdName</strong> product (primary key $SubPrimaryKey).\r\n          #if ($QuotaResetDate != "")\r\n          This quota will be renewed on $QuotaResetDate.\r\n          #else\r\n          This quota will not be renewed.\r\n          #end\r\n        </p>\r\n    <p>Below are details on quota usage for the subscription:</p>\r\n    <p>\r\n      <table>\r\n        <thead>\r\n          <th class="text">Quota Scope</th>\r\n          <th class="number">Calls</th>\r\n          <th class="number">Call Quota</th>\r\n          <th class="number">Bandwidth</th>\r\n          <th class="number">Bandwidth Quota</th>\r\n        </thead>\r\n        <tbody>\r\n          <tr>\r\n            <td class="text">Subscription</td>\r\n            <td class="number">\r\n                  #if ($CallsAlert == true)\r\n                  <span class="alert">$Calls</span>\r\n                  #else\r\n                  $Calls\r\n                  #end\r\n                </td>\r\n            <td class="number">$CallQuota</td>\r\n            <td class="number">\r\n                  #if ($BandwidthAlert == true)\r\n                  <span class="alert">$Bandwidth</span>\r\n                  #else\r\n                  $Bandwidth\r\n                  #end\r\n                </td>\r\n            <td class="number">$BandwidthQuota</td>\r\n          </tr>\r\n              #foreach ($api in $Apis)\r\n              <tr><td class="child1 text">API: $api.Name</td><td class="number">\r\n                  #if ($api.CallsAlert == true)\r\n                  <span class="alert">$api.Calls</span>\r\n                  #else\r\n                  $api.Calls\r\n                  #end\r\n                </td><td class="number">$api.CallQuota</td><td class="number">\r\n                  #if ($api.BandwidthAlert == true)\r\n                  <span class="alert">$api.Bandwidth</span>\r\n                  #else\r\n                  $api.Bandwidth\r\n                  #end\r\n                </td><td class="number">$api.BandwidthQuota</td></tr>\r\n              #foreach ($operation in $api.Operations)\r\n              <tr><td class="child2 text">Operation: $operation.Name</td><td class="number">\r\n                  #if ($operation.CallsAlert == true)\r\n                  <span class="alert">$operation.Calls</span>\r\n                  #else\r\n                  $operation.Calls\r\n                  #end\r\n                </td><td class="number">$operation.CallQuota</td><td class="number">\r\n                  #if ($operation.BandwidthAlert == true)\r\n                  <span class="alert">$operation.Bandwidth</span>\r\n                  #else\r\n                  $operation.Bandwidth\r\n                  #end\r\n                </td><td class="number">$operation.BandwidthQuota</td></tr>\r\n              #end\r\n              #end\r\n            </tbody>\r\n      </table>\r\n    </p>\r\n    <p>Thank you,</p>\r\n    <p>$OrganizationName API Team</p>\r\n    <a href="$DevPortalUrl">$DevPortalUrl</a>\r\n    <p />\r\n  </body>\r\n</html>'
    title: 'Developer quota limit approaching notification'
    description: 'Developers receive this email to alert them when they are approaching a quota limit.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'ProdName'
        title: 'Product name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'SubPrimaryKey'
        title: 'Primary Subscription key'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
      {
        name: 'QuotaResetDate'
        title: 'Quota reset date'
      }
    ]
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_RejectDeveloperNotificationMessage 'Microsoft.ApiManagement/service/templates@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'RejectDeveloperNotificationMessage'
  properties: {
    subject: 'Your subscription request for the $ProdName'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          We would like to inform you that we reviewed your subscription request for the <strong>$ProdName</strong>.\r\n        </p>\r\n        #if ($SubDeclineReason == "")\r\n        <p style="font-size:12pt;font-family:\'Segoe UI\'">Regretfully, we were unable to approve it, as subscriptions are temporarily suspended at this time.</p>\r\n        #else\r\n        <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          Regretfully, we were unable to approve it at this time for the following reason:\r\n          <div style="margin-left: 1.5em;"> $SubDeclineReason </div></p>\r\n        #end\r\n        <p style="font-size:12pt;font-family:\'Segoe UI\'"> We truly appreciate your interest. </p><p style="font-size:12pt;font-family:\'Segoe UI\'">All the best,</p><p style="font-size:12pt;font-family:\'Segoe UI\'">The $OrganizationName API Team</p><a style="font-size:12pt;font-family:\'Segoe UI\'" href="http://$DevPortalUrl">$DevPortalUrl</a></body>\r\n</html>'
    title: 'Subscription request declined'
    description: 'This email is sent to developers when their subscription requests for products requiring publisher approval is declined.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'SubDeclineReason'
        title: 'Reason for declining subscription'
      }
      {
        name: 'ProdName'
        title: 'Product name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_RequestDeveloperNotificationMessage 'Microsoft.ApiManagement/service/templates@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'RequestDeveloperNotificationMessage'
  properties: {
    subject: 'Your subscription request for the $ProdName'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          Thank you for your interest in our <strong>$ProdName</strong> API product!\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          We were delighted to receive your subscription request. We will promptly review it and get back to you at <strong>$DevEmail</strong>.\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">The $OrganizationName API Team</p>\r\n    <a style="font-size:12pt;font-family:\'Segoe UI\'" href="http://$DevPortalUrl">$DevPortalUrl</a>\r\n  </body>\r\n</html>'
    title: 'Subscription request received'
    description: 'This email is sent to developers to acknowledge receipt of their subscription requests for products requiring publisher approval.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'DevEmail'
        title: 'Developer email'
      }
      {
        name: 'ProdName'
        title: 'Product name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_1 'Microsoft.ApiManagement/service/users@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: '1'
  properties: {
    firstName: 'Administrator'
    email: 'admin@contoso.com'
    state: 'active'
    identities: [
      {
        provider: 'Azure'
        id: 'admin@contoso.com'
      }
    ]
    lastName: users_1_lastName
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_openai_api_chat_completions 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_openai_api
  name: 'chat-completions'
  properties: {
    displayName: 'Chat Completions'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/chat/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        type: 'string'
        required: true
        values: []
      }
    ]
    responses: []
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_openai_api_completions 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_openai_api
  name: 'completions'
  properties: {
    displayName: 'Completions'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        type: 'string'
        required: true
        values: []
      }
    ]
    responses: []
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_openai_api_embeddings 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_openai_api
  name: 'embeddings'
  properties: {
    displayName: 'Embeddings'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/embeddings'
    templateParameters: [
      {
        name: 'deployment-id'
        type: 'string'
        required: true
        values: []
      }
    ]
    responses: []
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_openai_api_get_deployment 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_openai_api
  name: 'get-deployment'
  properties: {
    displayName: 'Get Deployment'
    method: 'GET'
    urlTemplate: '/deployments/{deployment-id}'
    templateParameters: [
      {
        name: 'deployment-id'
        type: 'string'
        required: true
        values: []
      }
    ]
    responses: []
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_chat_app_api_get_frontend 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_chat_app_api
  name: 'get-frontend'
  properties: {
    displayName: 'Get Chat Frontend'
    method: 'GET'
    urlTemplate: '/'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_chat_app_api_get_health 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_chat_app_api
  name: 'get-health'
  properties: {
    displayName: 'Health Check'
    method: 'GET'
    urlTemplate: '/health'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_chat_app_api_get_models 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_chat_app_api
  name: 'get-models'
  properties: {
    displayName: 'List Discovered Models'
    method: 'GET'
    urlTemplate: '/api/models'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_chat_app_api_get_static 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_chat_app_api
  name: 'get-static'
  properties: {
    displayName: 'Static Assets'
    method: 'GET'
    urlTemplate: '/static/*'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_openai_api_list_deployments 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_openai_api
  name: 'list-deployments'
  properties: {
    displayName: 'List Deployments'
    method: 'GET'
    urlTemplate: '/deployments'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_chat_app_api_post_agent_chat 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_chat_app_api
  name: 'post-agent-chat'
  properties: {
    displayName: 'Agent Chat API'
    method: 'POST'
    urlTemplate: '/api/agent/chat'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_chat_app_api_post_chat 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_chat_app_api
  name: 'post-chat'
  properties: {
    displayName: 'Chat API'
    method: 'POST'
    urlTemplate: '/api/chat'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_chat_app_api_post_hosted_chat 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_chat_app_api
  name: 'post-hosted-chat'
  properties: {
    displayName: 'Hosted Agent Chat API'
    method: 'POST'
    urlTemplate: '/api/hosted/chat'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_chat_app_api_policy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_chat_app_api
  name: 'policy'
  properties: {
    value: '<policies>\r\n  <inbound>\r\n    <base />\r\n    <set-backend-service backend-id="chat-app-backend" />\r\n    <cors allow-credentials="false">\r\n      <allowed-origins>\r\n        <origin>*</origin>\r\n      </allowed-origins>\r\n      <allowed-methods>\r\n        <method>GET</method>\r\n        <method>POST</method>\r\n      </allowed-methods>\r\n      <allowed-headers>\r\n        <header>Content-Type</header>\r\n      </allowed-headers>\r\n    </cors>\r\n  </inbound>\r\n  <backend>\r\n    <base />\r\n  </backend>\r\n  <outbound>\r\n    <base />\r\n  </outbound>\r\n  <on-error>\r\n    <base />\r\n  </on-error>\r\n</policies>'
    format: 'xml'
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_openai_api_policy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_openai_api
  name: 'policy'
  properties: {
    value: '<policies>\r\n  <inbound>\r\n    <base />\r\n    <!-- Authenticate to Azure AI Services backend with APIM managed identity -->\r\n    <authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="managed-id-access-token" ignore-error="false" />\r\n    <set-header name="Authorization" exists-action="override">\r\n      <value>@("Bearer " + (string)context.Variables["managed-id-access-token"])</value>\r\n    </set-header>\r\n    <!-- Remove client subscription key from backend request -->\r\n    <set-header name="api-key" exists-action="delete" />\r\n    <!-- Default api-version if caller omits it -->\r\n    <set-query-parameter name="api-version" exists-action="skip">\r\n      <value>2024-10-21</value>\r\n    </set-query-parameter>\r\n    <!-- Rate limiting: 100 calls per minute per subscription -->\r\n    <rate-limit calls="100" renewal-period="60" />\r\n    <!-- Route to Foundry backend -->\r\n    <set-backend-service backend-id="foundry-backend" />\r\n  </inbound>\r\n  <backend>\r\n    <base />\r\n  </backend>\r\n  <outbound>\r\n    <base />\r\n  </outbound>\r\n  <on-error>\r\n    <base />\r\n  </on-error>\r\n</policies>'
    format: 'xml'
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_applicationinsights 'Microsoft.ApiManagement/service/diagnostics@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
    loggerId: service_apim_aigw_aigw2_ea4ky5_name_appinsights_logger.id
    sampling: {
      samplingType: 'fixed'
      percentage: json('100')
    }
    frontend: {
      request: {
        headers: []
        body: {
          bytes: 0
        }
      }
      response: {
        headers: []
        body: {
          bytes: 0
        }
      }
    }
    backend: {
      request: {
        headers: []
        body: {
          bytes: 0
        }
      }
      response: {
        headers: []
        body: {
          bytes: 0
        }
      }
    }
  }
}

resource Microsoft_ApiManagement_service_diagnostics_service_apim_aigw_aigw2_ea4ky5_name_azuremonitor 'Microsoft.ApiManagement/service/diagnostics@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'azuremonitor'
  properties: {
    logClientIp: true
    loggerId: service_apim_aigw_aigw2_ea4ky5_name_azuremonitor.id
    sampling: {
      samplingType: 'fixed'
      percentage: json('100')
    }
    frontend: {
      request: {
        dataMasking: {
          queryParams: [
            {
              value: '*'
              mode: 'Hide'
            }
          ]
        }
      }
    }
    backend: {
      request: {
        dataMasking: {
          queryParams: [
            {
              value: '*'
              mode: 'Hide'
            }
          ]
        }
      }
    }
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_applicationinsights_appinsights_logger 'Microsoft.ApiManagement/service/diagnostics/loggers@2018-01-01' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_applicationinsights
  name: 'appinsights-logger'
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_azuremonitor_azuremonitor 'Microsoft.ApiManagement/service/diagnostics/loggers@2018-01-01' = {
  parent: Microsoft_ApiManagement_service_diagnostics_service_apim_aigw_aigw2_ea4ky5_name_azuremonitor
  name: 'azuremonitor'
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_administrators_1 'Microsoft.ApiManagement/service/groups/users@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_administrators
  name: '1'
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_developers_1 'Microsoft.ApiManagement/service/groups/users@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_developers
  name: '1'
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_model_gateway_openai_api 'Microsoft.ApiManagement/service/products/apis@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_model_gateway
  name: 'openai-api'
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_model_gateway_administrators 'Microsoft.ApiManagement/service/products/groups@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_model_gateway
  name: 'administrators'
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_spoke_subscription 'Microsoft.ApiManagement/service/subscriptions@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_resource
  name: 'spoke-subscription'
  properties: {
    scope: service_apim_aigw_aigw2_ea4ky5_name_model_gateway.id
    displayName: 'Spoke Consumer Subscription'
    state: 'active'
    allowTracing: false
  }
}

resource service_apim_aigw_aigw2_ea4ky5_name_openai_api_get_deployment_policy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_openai_api_get_deployment
  name: 'policy'
  properties: {
    value: '<policies>\r\n  <inbound>\r\n    <authentication-managed-identity resource="https://management.azure.com/" />\r\n    <rewrite-uri template="/deployments/{deployment-id}?api-version=2023-05-01" copy-unmatched-params="false" />\r\n    <set-backend-service base-url="https://management.azure.com//subscriptions/5c9ecf91-0bc3-472b-a051-059f1c37767c/resourceGroups/rg-aigw2-aigw-hub/providers/Microsoft.CognitiveServices/accounts/ais-aigw-hub-aigw2-ea4ky5" />\r\n  </inbound>\r\n  <backend>\r\n    <base />\r\n  </backend>\r\n  <outbound>\r\n    <base />\r\n  </outbound>\r\n  <on-error>\r\n    <base />\r\n  </on-error>\r\n</policies>'
    format: 'xml'
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_openai_api
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_openai_api_list_deployments_policy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_openai_api_list_deployments
  name: 'policy'
  properties: {
    value: '<policies>\r\n  <inbound>\r\n    <authentication-managed-identity resource="https://management.azure.com/" />\r\n    <rewrite-uri template="/deployments?api-version=2023-05-01" copy-unmatched-params="false" />\r\n    <set-backend-service base-url="https://management.azure.com//subscriptions/5c9ecf91-0bc3-472b-a051-059f1c37767c/resourceGroups/rg-aigw2-aigw-hub/providers/Microsoft.CognitiveServices/accounts/ais-aigw-hub-aigw2-ea4ky5" />\r\n  </inbound>\r\n  <backend>\r\n    <base />\r\n  </backend>\r\n  <outbound>\r\n    <base />\r\n  </outbound>\r\n  <on-error>\r\n    <base />\r\n  </on-error>\r\n</policies>'
    format: 'xml'
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_openai_api
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_model_gateway_69a6b8a2bf32fb130cefcf0a 'Microsoft.ApiManagement/service/products/apiLinks@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_model_gateway
  name: '69a6b8a2bf32fb130cefcf0a'
  properties: {
    apiId: service_apim_aigw_aigw2_ea4ky5_name_openai_api.id
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}

resource service_apim_aigw_aigw2_ea4ky5_name_model_gateway_69a6b8a1bf32fb130cefcf08 'Microsoft.ApiManagement/service/products/groupLinks@2024-06-01-preview' = {
  parent: service_apim_aigw_aigw2_ea4ky5_name_model_gateway
  name: '69a6b8a1bf32fb130cefcf08'
  properties: {
    groupId: service_apim_aigw_aigw2_ea4ky5_name_administrators.id
  }
  dependsOn: [
    service_apim_aigw_aigw2_ea4ky5_name_resource
  ]
}
