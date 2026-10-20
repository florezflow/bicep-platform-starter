metadata name = 'Management groups'
metadata description = 'Deployment 1 of an environment: the management group hierarchy of the Azure landing zone, and which subscription sits where. Deploys at the tenant root group.'
metadata version = '1.0.0'

targetScope = 'managementGroup'

import { subscriptionPlacementType } from 'br/platform:types:v1.0.0'

// --- Types ---

@description('The root of the hierarchy, right under the tenant root group.')
type rootType = {
  @description('ID of the root management group. The groups below it are named <id>-platform, <id>-platform-identity, and so on.')
  @metadata({ example: 'contoso' })
  id: string

  @description('Display name of the root management group.')
  @metadata({ example: 'Contoso' })
  displayName: string
}

// --- Parameters ---

@description('The root of the hierarchy.')
param pRoot rootType

@description('Subscriptions and the management group each one belongs in.')
param pPlacements subscriptionPlacementType[] = []

// --- Variables ---

var vPlatformGroups = [
  { key: 'security', displayName: 'Security' }
  { key: 'management', displayName: 'Management' }
  { key: 'connectivity', displayName: 'Connectivity' }
  { key: 'identity', displayName: 'Identity' }
]

var vLandingZoneGroups = [
  { key: 'corp', displayName: 'Corp' }
  { key: 'online', displayName: 'Online' }
]

// --- Resources ---

// Management groups are tenant resources: a management group stack declares them with scope tenant()
resource rRoot 'Microsoft.Management/managementGroups@2023-04-01' = {
  scope: tenant()
  name: pRoot.id
  properties: {
    displayName: pRoot.displayName
    details: {
      parent: {
        id: tenantResourceId('Microsoft.Management/managementGroups', tenant().tenantId)
      }
    }
  }
}

resource rPlatform 'Microsoft.Management/managementGroups@2023-04-01' = {
  scope: tenant()
  name: '${pRoot.id}-platform'
  properties: {
    displayName: 'Platform'
    details: { parent: { id: rRoot.id } }
  }
}

resource rLandingZones 'Microsoft.Management/managementGroups@2023-04-01' = {
  scope: tenant()
  name: '${pRoot.id}-landingzones'
  properties: {
    displayName: 'Landing zones'
    details: { parent: { id: rRoot.id } }
  }
}

resource rSandbox 'Microsoft.Management/managementGroups@2023-04-01' = {
  scope: tenant()
  name: '${pRoot.id}-sandbox'
  properties: {
    displayName: 'Sandbox'
    details: { parent: { id: rRoot.id } }
  }
}

resource rDecommissioned 'Microsoft.Management/managementGroups@2023-04-01' = {
  scope: tenant()
  name: '${pRoot.id}-decommissioned'
  properties: {
    displayName: 'Decommissioned'
    details: { parent: { id: rRoot.id } }
  }
}

resource rPlatformGroups 'Microsoft.Management/managementGroups@2023-04-01' = [
  for group in vPlatformGroups: {
    scope: tenant()
    name: '${pRoot.id}-platform-${group.key}'
    properties: {
      displayName: group.displayName
      details: { parent: { id: rPlatform.id } }
    }
  }
]

resource rLandingZoneGroups 'Microsoft.Management/managementGroups@2023-04-01' = [
  for group in vLandingZoneGroups: {
    scope: tenant()
    name: '${pRoot.id}-landingzones-${group.key}'
    properties: {
      displayName: group.displayName
      details: { parent: { id: rLandingZones.id } }
    }
  }
]

resource rPlacements 'Microsoft.Management/managementGroups/subscriptions@2023-04-01' = [
  for placement in pPlacements: {
    scope: tenant()
    name: '${pRoot.id}-${placement.group}/${placement.subscriptionId}'
    dependsOn: [rPlatformGroups, rLandingZoneGroups, rSandbox, rDecommissioned]
  }
]

// --- Outputs ---

@description('ID of the root management group.')
output oRootId string = rRoot.name

@description('ID of the platform management group, where the platform stack deploys.')
output oPlatformId string = rPlatform.name
