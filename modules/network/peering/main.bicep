metadata name = 'Virtual network peering'
metadata description = 'One direction of a peering, from an existing virtual network to another one. A working peering needs both directions.'
metadata version = '1.0.0'

// --- Parameters ---

@description('Name of the existing virtual network the peering starts from, in the resource group this module deploys to.')
@metadata({ example: 'vnet-sampleapp-prod-szn-001' })
param pVnetName string

@description('Resource ID of the virtual network on the other side.')
param pRemoteVnetId string

@description('Let the other side use this network\'s gateway. Set on the hub side when the hub has a gateway.')
param pAllowGatewayTransit bool = false

@description('Use the gateway of the other side. Set on the spoke side when the hub has a gateway; never for Entra Domain Services.')
param pUseRemoteGateways bool = false

// --- Resources ---

resource rVnet 'Microsoft.Network/virtualNetworks@2026-01-01' existing = {
  name: pVnetName
}

resource rPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2026-01-01' = {
  parent: rVnet
  name: 'peer-to-${last(split(pRemoteVnetId, '/'))}'
  properties: {
    remoteVirtualNetwork: {
      id: pRemoteVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: pAllowGatewayTransit
    useRemoteGateways: pUseRemoteGateways
  }
}

// --- Outputs ---

@description('Name of the peering.')
output oName string = rPeering.name
