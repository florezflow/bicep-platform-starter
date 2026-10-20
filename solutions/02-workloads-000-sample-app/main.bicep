metadata name = 'Sample app'
metadata description = 'One workload in its own subscription: a spoke network peered with the hub, a subnet with its own network security group, and a storage account only that subnet can reach.'
metadata version = '1.0.0'

targetScope = 'subscription'

import { contextType, hubVnetType, resourceName, securityRuleType, storageSkuType } from 'br/platform:types:v1.0.0'

// --- Parameters ---

@description('Where the workload is deployed.')
param pContext contextType

@description('The hub to peer with. The platform stack owns it; this stack owns both halves of the peering.')
param pHub hubVnetType

@description('Address space of the spoke. The app subnet gets the first /26.')
@metadata({ example: '10.10.16.0/24' })
param pAddressPrefix string

@description('Security rules for the app subnet.')
param pSecurityRules securityRuleType[] = []

@description('Redundancy of the storage account.')
param pStorageSku storageSkuType = 'Standard_ZRS'

@description('DNS servers of the spoke. Empty uses the Azure-provided DNS.')
@metadata({ example: ['10.10.4.4', '10.10.4.5'] })
param pDnsServers string[] = []

// --- Resources ---

resource rRg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceName('rg', 'sampleapp', pContext, 1)
  location: pContext.location
  tags: pContext.?tags
}

// --- Modules ---

module mVnet 'br/platform:modules/network/vnet:v1.0.0' = {
  scope: rRg
  params: {
    pContext: pContext
    pName: 'sampleapp'
    pAddressPrefixes: [pAddressPrefix]
    pDnsServers: pDnsServers
  }
}

module mAppNetwork 'br/platform:modules/network/app-network:v1.0.0' = {
  scope: rRg
  params: {
    pContext: pContext
    pVnetName: mVnet.outputs.oName
    pName: 'app'
    pAddressPrefix: cidrSubnet(pAddressPrefix, 26, 0)
    pSecurityRules: pSecurityRules
    pServiceEndpoints: ['Microsoft.Storage']
  }
}

module mStorage 'br/platform:modules/storage/account:v1.0.0' = {
  scope: rRg
  params: {
    pContext: pContext
    pName: 'sampleapp'
    pSku: pStorageSku
    pAllowedSubnetIds: [mAppNetwork.outputs.oSubnetId]
  }
}

// Both halves belong to this stack: retiring the workload removes its peering from the hub too
module mPeeringToHub 'br/platform:modules/network/peering:v1.0.0' = {
  scope: rRg
  params: {
    pVnetName: mVnet.outputs.oName
    pRemoteVnetId: resourceId(pHub.subscriptionId, pHub.resourceGroupName, 'Microsoft.Network/virtualNetworks', pHub.name)
  }
  dependsOn: [mAppNetwork] // one change at a time per virtual network
}

module mPeeringFromHub 'br/platform:modules/network/peering:v1.0.0' = {
  scope: resourceGroup(pHub.subscriptionId, pHub.resourceGroupName)
  params: {
    pVnetName: pHub.name
    pRemoteVnetId: mVnet.outputs.oId
  }
}

// --- Outputs ---

@description('Resource group of the workload.')
output oResourceGroupName string = rRg.name

@description('Name of the storage account.')
output oStorageAccountName string = mStorage.outputs.oName
