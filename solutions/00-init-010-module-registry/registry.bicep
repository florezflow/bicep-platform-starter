// The registry and who may push or pull. Part of the module-registry solution, not a module of its own.

// --- Parameters ---

@description('Name of the registry.')
param pName string

@description('Azure region of the registry.')
param pLocation string

@description('Tags added to the registry.')
param pTags object

@description('Object IDs that may publish (AcrPush).')
param pPushPrincipalIds string[]

@description('Object IDs that may restore (AcrPull).')
param pPullPrincipalIds string[]

// --- Variables ---

// Built-in role definition IDs
var vAcrPush = '8311e382-0749-4cb8-b61a-304f252e45ec'
var vAcrPull = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// --- Resources ---

resource rRegistry 'Microsoft.ContainerRegistry/registries@2025-11-01' = {
  name: pName
  location: pLocation
  tags: pTags
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
  }
}

resource rPush 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in pPushPrincipalIds: {
    scope: rRegistry
    name: guid(rRegistry.id, principalId, vAcrPush)
    properties: {
      principalId: principalId
      principalType: 'ServicePrincipal'
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vAcrPush)
    }
  }
]

resource rPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in pPullPrincipalIds: {
    scope: rRegistry
    name: guid(rRegistry.id, principalId, vAcrPull)
    properties: {
      principalId: principalId
      principalType: 'ServicePrincipal'
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vAcrPull)
    }
  }
]

// --- Outputs ---

@description('Login server of the registry.')
output oLoginServer string = rRegistry.properties.loginServer
