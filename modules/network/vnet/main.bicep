metadata name = 'Virtual network'
metadata description = 'A virtual network without subnets. Each subnet is its own resource, so redeploying the network never touches them.'
metadata version = '1.0.0'

import { contextType, resourceName } from 'br/platform:types:v1.0.0'

// --- Parameters ---

@description('Where the virtual network is deployed.')
param pContext contextType

@description('Purpose of the virtual network, used in its name.')
@metadata({ example: 'hub' })
param pName string

@description('Address space of the virtual network.')
@metadata({ example: ['10.10.0.0/22'] })
param pAddressPrefixes string[]

@description('DNS servers for the virtual network. Empty uses the Azure-provided DNS.')
@metadata({ example: ['10.10.4.4', '10.10.4.5'] })
param pDnsServers string[] = []

// --- Resources ---

// No subnets property on purpose: a PUT without it leaves existing subnets alone,
// while `subnets: []` would delete every subnet in the network.
resource rVnet 'Microsoft.Network/virtualNetworks@2026-01-01' = {
  name: resourceName('vnet', pName, pContext, 1)
  location: pContext.location
  tags: pContext.?tags
  properties: {
    addressSpace: {
      addressPrefixes: pAddressPrefixes
    }
    dhcpOptions: empty(pDnsServers) ? null : { dnsServers: pDnsServers }
  }
}

// --- Outputs ---

@description('Name of the virtual network.')
output oName string = rVnet.name

@description('Resource ID of the virtual network.')
output oId string = rVnet.id
