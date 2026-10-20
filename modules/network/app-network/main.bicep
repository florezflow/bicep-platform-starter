metadata name = 'App network'
metadata description = 'A subnet with its own network security group, for one purpose in an existing virtual network.'
metadata version = '1.0.0'

import { contextType, securityRuleType } from 'br/platform:types:v1.0.0'

// --- Parameters ---

@description('Where the subnet and its network security group are deployed.')
param pContext contextType

@description('Name of the existing virtual network, in the resource group this module deploys to.')
@metadata({ example: 'vnet-sampleapp-prod-szn-001' })
param pVnetName string

@description('Purpose of the subnet, used in the names of the subnet and its network security group.')
@metadata({ example: 'app' })
param pName string

@description('Address range of the subnet.')
@metadata({ example: '10.10.16.0/26' })
param pAddressPrefix string

@description('Security rules for the subnet.')
param pSecurityRules securityRuleType[] = []

@description('Service endpoints to enable on the subnet.')
@metadata({ example: ['Microsoft.Storage'] })
param pServiceEndpoints string[] = []

// --- Modules ---

module mNsg 'br/platform:modules/network/nsg:v1.0.0' = {
  params: {
    pContext: pContext
    pName: pName
    pSecurityRules: pSecurityRules
  }
}

module mSubnet 'br/platform:modules/network/subnet:v1.0.0' = {
  params: {
    pContext: pContext
    pVnetName: pVnetName
    pName: pName
    pAddressPrefix: pAddressPrefix
    pNsgId: mNsg.outputs.oId
    pServiceEndpoints: pServiceEndpoints
  }
}

// --- Outputs ---

@description('Resource ID of the subnet.')
output oSubnetId string = mSubnet.outputs.oId

@description('Resource ID of the network security group.')
output oNsgId string = mNsg.outputs.oId
