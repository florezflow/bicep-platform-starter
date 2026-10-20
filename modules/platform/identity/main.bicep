metadata name = 'Platform: identity'
metadata description = 'Microsoft Entra Domain Services in its own spoke, peered with the hub. No domain controller VMs to patch.'
metadata version = '1.0.0'

targetScope = 'subscription'

import { contextType, domainServicesType, hubVnetType, resourceName } from 'br/platform:types:v1.0.0'

// --- Parameters ---

@description('Where the identity spoke is deployed.')
param pContext contextType

@description('Address space of the identity spoke. The managed domain gets the first /27.')
@metadata({ example: '10.10.4.0/24' })
param pAddressPrefix string

@description('The hub to peer with.')
param pHub hubVnetType

@description('The managed domain. Leave it out where the tenant already has one: a tenant can have only one.')
param pDomainServices domainServicesType?

@description('DNS servers of the spoke. Once the managed domain runs, its two IP addresses.')
@metadata({ example: ['10.10.4.4', '10.10.4.5'] })
param pDnsServers string[] = []

// --- Variables ---

// What the managed domain needs to be managed and supported (Microsoft Learn: network considerations)
var vDomainServicesRules = [
  {
    name: 'allow-rdp-from-corpnetsaw'
    priority: 201
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: 'CorpNetSaw'
    destinationPortRange: '3389'
  }
  {
    name: 'allow-psremoting-from-domainservices'
    priority: 301
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: 'AzureActiveDirectoryDomainServices'
    destinationPortRange: '5986'
  }
]

// --- Resources ---

resource rRg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceName('rg', 'identity', pContext, 1)
  location: pContext.location
  tags: pContext.?tags
}

// --- Modules ---

module mVnet 'br/platform:modules/network/vnet:v1.0.0' = {
  scope: rRg
  params: {
    pContext: pContext
    pName: 'identity'
    pAddressPrefixes: [pAddressPrefix]
    pDnsServers: pDnsServers
  }
}

module mDomainServicesNetwork 'br/platform:modules/network/app-network:v1.0.0' = {
  scope: rRg
  params: {
    pContext: pContext
    pVnetName: mVnet.outputs.oName
    pName: 'domainservices'
    pAddressPrefix: cidrSubnet(pAddressPrefix, 27, 0)
    pSecurityRules: vDomainServicesRules
  }
}

module mDomainServices 'br/platform:modules/identity/domain-services:v1.0.0' = if (pDomainServices != null) {
  scope: rRg
  params: {
    pContext: pContext
    pDomainServices: pDomainServices!
    pSubnetId: mDomainServicesNetwork.outputs.oSubnetId
  }
}

// Entra Domain Services doesn't support remote gateways on its peering
module mPeeringToHub 'br/platform:modules/network/peering:v1.0.0' = {
  scope: rRg
  params: {
    pVnetName: mVnet.outputs.oName
    pRemoteVnetId: resourceId(pHub.subscriptionId, pHub.resourceGroupName, 'Microsoft.Network/virtualNetworks', pHub.name)
    pUseRemoteGateways: false
  }
  dependsOn: [mDomainServicesNetwork] // one change at a time per virtual network
}

module mPeeringFromHub 'br/platform:modules/network/peering:v1.0.0' = {
  scope: resourceGroup(pHub.subscriptionId, pHub.resourceGroupName)
  params: {
    pVnetName: pHub.name
    pRemoteVnetId: mVnet.outputs.oId
  }
}

// --- Outputs ---

@description('Resource ID of the identity spoke.')
output oVnetId string = mVnet.outputs.oId
