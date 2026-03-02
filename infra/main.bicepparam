using './main.bicep'

param location = readEnvironmentVariable('AZURE_LOCATION', 'swedencentral')
param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'dev')
param projectName = 'aigw'
param deploySpokeFoundry = false
param publisherEmail = readEnvironmentVariable('APIM_PUBLISHER_EMAIL', 'admin@contoso.com')
param publisherName = 'AI Gateway Team'
param hubResourceGroupName = readEnvironmentVariable('AZURE_HUB_RESOURCE_GROUP', 'rg-${readEnvironmentVariable('AZURE_ENV_NAME', 'dev')}-aigw-hub')
param spokeResourceGroupName = readEnvironmentVariable('AZURE_SPOKE_RESOURCE_GROUP', 'rg-${readEnvironmentVariable('AZURE_ENV_NAME', 'dev')}-aigw-spoke')
param chatAgentImage = readEnvironmentVariable('CHAT_AGENT_IMAGE', 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest')
param chatAgentPort = int(readEnvironmentVariable('CHAT_AGENT_PORT', '80'))
