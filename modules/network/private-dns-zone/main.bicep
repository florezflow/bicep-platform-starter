metadata name = 'Private DNS zone'
metadata description = 'A private DNS zone, linked to the virtual networks that resolve it.'
metadata version = '1.0.0'

import { contextType } from 'br/platform:types:v1.0.0'

// --- Parameters ---

@description('Where the zone is deployed. Private DNS zones are global, so only the tags apply.')
param pContext contextType

@description('Name of the zone.')
@metadata({ example: 'privatelink.blob.core.windows.net' })
param pZoneName string

@description('Resource IDs of the virtual networks that resolve the zone.')
param pVnetIds string[] = []

// --- Resources ---

resource rZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: pZoneName
  location: 'global'
  tags: pContext.?tags
}

resource rLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for vnetId in pVnetIds: {
    parent: rZone
    name: 'link-to-${last(split(vnetId, '/'))}'
    location: 'global'
    tags: pContext.?tags
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnetId
      }
    }
  }
]

// --- Outputs ---

@description('Resource ID of the zone.')
output oId string = rZone.id
