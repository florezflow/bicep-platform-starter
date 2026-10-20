metadata name = 'Subnet'
metadata description = 'A subnet in an existing virtual network, owned by the stack that deploys it.'
metadata version = '1.0.0'

import { contextType, resourceName } from 'br/platform:types:v1.0.0'

// --- Parameters ---

@description('Where the subnet is deployed.')
param pContext contextType

@description('Name of the existing virtual network, in the resource group this module deploys to.')
@metadata({ example: 'vnet-hub-prod-szn-001' })
param pVnetName string

@description('Purpose of the subnet, used in its name. Names Azure reserves for its own services are kept as they are.')
@metadata({ example: 'app' })
param pName string

@description('Address range of the subnet, inside the address space of the virtual network.')
@metadata({ example: '10.10.16.0/26' })
param pAddressPrefix string

@description('Resource ID of the network security group to attach. Without it, the subnet has none.')
param pNsgId string?

@description('Service endpoints to enable on the subnet.')
@metadata({ example: ['Microsoft.Storage'] })
param pServiceEndpoints string[] = []

// --- Variables ---

var vReservedNames = ['GatewaySubnet', 'AzureFirewallSubnet', 'AzureFirewallManagementSubnet', 'AzureBastionSubnet']
var vReserved = contains(vReservedNames, pName)

// --- Resources ---

resource rVnet 'Microsoft.Network/virtualNetworks@2026-01-01' existing = {
  name: pVnetName
}

resource rSubnet 'Microsoft.Network/virtualNetworks/subnets@2026-01-01' = {
  parent: rVnet
  name: vReserved ? pName : resourceName('snet', pName, pContext, 1)
  properties: {
    addressPrefix: pAddressPrefix
    defaultOutboundAccess: vReserved ? null : false
    networkSecurityGroup: pNsgId == null ? null : { id: pNsgId! }
    serviceEndpoints: [for service in pServiceEndpoints: { service: service }]
  }
}

// --- Outputs ---

@description('Name of the subnet.')
output oName string = rSubnet.name

@description('Resource ID of the subnet.')
output oId string = rSubnet.id
