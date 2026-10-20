metadata name = 'Platform: connectivity'
metadata description = 'The hub of an environment: its virtual network, the subnets Azure Firewall and a VPN or ExpressRoute gateway would use, and the private DNS zone for blob storage.'
metadata version = '1.0.0'

targetScope = 'subscription'

import { contextType, hubVnetType, resourceName } from 'br/platform:types:v1.0.0'

// --- Parameters ---

@description('Where the hub is deployed.')
param pContext contextType

@description('Address space of the hub. The first /26 is reserved for Azure Firewall, the /27 after it for a gateway.')
@metadata({ example: '10.10.0.0/22' })
param pAddressPrefix string

// --- Resources ---

resource rRg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceName('rg', 'hub', pContext, 1)
  location: pContext.location
  tags: pContext.?tags
}

// --- Modules ---

module mVnet 'br/platform:modules/network/vnet:v1.0.0' = {
  scope: rRg
  params: {
    pContext: pContext
    pName: 'hub'
    pAddressPrefixes: [pAddressPrefix]
  }
}

// Reserved and empty: the firewall and the gateway are separate decisions, with their own cost
module mFirewallSubnet 'br/platform:modules/network/subnet:v1.0.0' = {
  scope: rRg
  params: {
    pContext: pContext
    pVnetName: mVnet.outputs.oName
    pName: 'AzureFirewallSubnet'
    pAddressPrefix: cidrSubnet(pAddressPrefix, 26, 0)
  }
}

module mGatewaySubnet 'br/platform:modules/network/subnet:v1.0.0' = {
  scope: rRg
  params: {
    pContext: pContext
    pVnetName: mVnet.outputs.oName
    pName: 'GatewaySubnet'
    pAddressPrefix: cidrSubnet(pAddressPrefix, 27, 2)
  }
  dependsOn: [mFirewallSubnet] // one subnet change at a time per virtual network
}

module mBlobZone 'br/platform:modules/network/private-dns-zone:v1.0.0' = {
  scope: rRg
  params: {
    pContext: pContext
    pZoneName: 'privatelink.blob.${environment().suffixes.storage}'
    pVnetIds: [mVnet.outputs.oId]
  }
}

// --- Outputs ---

@description('The hub, for the spokes that peer with it.')
output oHub hubVnetType = {
  subscriptionId: subscription().subscriptionId
  resourceGroupName: rRg.name
  name: mVnet.outputs.oName
}

@description('Resource ID of the hub virtual network.')
output oVnetId string = mVnet.outputs.oId
