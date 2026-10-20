// Deployed once by an admin, from source: scripts/deploy-stack.sh 00-init-010-module-registry/prod deploy
using '../main.bicep'

var vPlatform = loadJsonContent('../../../platform.json')

param pRegistryName = vPlatform.registry.name
param pResourceGroupName = 'rg-registry-prod-szn-001'
param pLocation = vPlatform.location
param pTags = {
  workload: 'platform'
  owner: 'platform-team'
}
param pDeployerPrincipalId = vPlatform.identities.deployerPrincipalId
param pPreviewerPrincipalId = vPlatform.identities.previewerPrincipalId
