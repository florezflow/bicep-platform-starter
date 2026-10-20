metadata name = 'Module registry'
metadata description = 'The Azure Container Registry every other component is published to. It has to exist before anything can be published, so it references nothing from it: an admin deploys it once, from source.'
metadata version = '1.0.0'

targetScope = 'subscription'

// --- Parameters ---

@description('Name of the registry: globally unique, letters and digits. The same name goes into bicepconfig.json.')
@metadata({ example: 'crplatformprodszn001' })
@minLength(5)
@maxLength(50)
param pRegistryName string

@description('Name of the resource group for the registry.')
@metadata({ example: 'rg-registry-prod-szn-001' })
param pResourceGroupName string

@description('Azure region of the registry.')
@metadata({ example: 'switzerlandnorth' })
param pLocation string

@description('Tags added to every resource.')
param pTags object = {}

@description('Object ID of the identity that publishes modules (AcrPush).')
param pDeployerPrincipalId string

@description('Object ID of the identity that previews deployments and restores modules (AcrPull).')
param pPreviewerPrincipalId string

// --- Resources ---

resource rRg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: pResourceGroupName
  location: pLocation
  tags: pTags
}

// --- Modules ---

module mRegistry 'registry.bicep' = {
  scope: rRg
  params: {
    pName: pRegistryName
    pLocation: pLocation
    pTags: pTags
    pPushPrincipalIds: [pDeployerPrincipalId]
    pPullPrincipalIds: [pPreviewerPrincipalId]
  }
}

// --- Outputs ---

@description('Login server of the registry, for the moduleAliases in bicepconfig.json.')
output oLoginServer string = mRegistry.outputs.oLoginServer
