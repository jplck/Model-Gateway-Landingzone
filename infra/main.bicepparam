using './main.bicep'

param location = readEnvironmentVariable('AZURE_LOCATION', 'swedencentral')
param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'dev')
param projectName = 'aigw'
param deploySpokeFoundry = false
param publisherEmail = readEnvironmentVariable('APIM_PUBLISHER_EMAIL', 'admin@contoso.com')
param publisherName = 'AI Gateway Team'
