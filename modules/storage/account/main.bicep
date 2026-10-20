metadata name = 'Storage account'
metadata description = 'A storage account that only accepts Entra ID and traffic from the given subnets.'
metadata version = '1.1.0'

import { contextType, storageSkuType } from 'br/platform:types:v1.0.0'

// --- Parameters ---

@description('Where the storage account is deployed.')
param pContext contextType

@description('Purpose of the storage account, lowercase letters and digits only. The name adds the environment and six characters that make it globally unique.')
@metadata({ example: 'sampleapp' })
@maxLength(10)
param pName string

@description('Redundancy of the storage account.')
param pSku storageSkuType = 'Standard_ZRS'

@description('Subnets that may reach the account. Each subnet needs the Microsoft.Storage service endpoint.')
param pAllowedSubnetIds string[] = []

@description('Blob containers to create, none of them public.')
@metadata({ example: ['uploads', 'reports'] })
param pContainers string[] = []

// --- Resources ---

resource rStorage 'Microsoft.Storage/storageAccounts@2026-06-01' = {
  name: toLower('st${pName}${pContext.environment}${take(uniqueString(resourceGroup().id), 6)}')
  location: pContext.location
  tags: pContext.?tags
  kind: 'StorageV2'
  sku: {
    name: pSku
  }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: [for subnetId in pAllowedSubnetIds: { id: subnetId, action: 'Allow' }]
    }
  }
}

resource rBlobServices 'Microsoft.Storage/storageAccounts/blobServices@2026-06-01' = if (!empty(pContainers)) {
  parent: rStorage
  name: 'default'
}

resource rContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2026-06-01' = [
  for container in pContainers: {
    parent: rBlobServices
    name: container
    properties: {
      publicAccess: 'None'
    }
  }
]

// --- Outputs ---

@description('Name of the storage account.')
output oName string = rStorage.name

@description('Resource ID of the storage account.')
output oId string = rStorage.id
