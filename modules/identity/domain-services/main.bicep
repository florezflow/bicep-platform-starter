metadata name = 'Microsoft Entra Domain Services'
metadata description = 'A managed domain with hardened security settings, in a dedicated subnet. Provisioning continues for up to an hour after the deployment returns.'
metadata version = '1.0.0'

import { contextType, domainServicesType } from 'br/platform:types:v1.0.0'

// --- Parameters ---

@description('Where the managed domain is deployed.')
param pContext contextType

@description('The managed domain. A tenant can have only one.')
param pDomainServices domainServicesType

@description('Resource ID of the dedicated subnet. It needs a network security group that allows the management traffic.')
param pSubnetId string

// --- Resources ---

resource rDomain 'Microsoft.AAD/domainServices@2025-06-01' = {
  name: pDomainServices.domainName
  location: pContext.location
  tags: pContext.?tags
  properties: {
    domainName: pDomainServices.domainName
    sku: pDomainServices.sku
    domainConfigurationType: 'FullySynced'
    filteredSync: 'Disabled'
    replicaSets: [
      {
        location: pContext.location
        subnetId: pSubnetId
      }
    ]
    notificationSettings: {
      notifyGlobalAdmins: 'Enabled'
      notifyDcAdmins: 'Enabled'
      additionalRecipients: pDomainServices.?notifyEmails ?? []
    }
    domainSecuritySettings: {
      ntlmV1: 'Disabled'
      tlsV1: 'Disabled'
      syncNtlmPasswords: 'Disabled'
      kerberosRc4Encryption: 'Disabled'
      kerberosArmoring: 'Enabled'
      ldapSigning: 'Enabled'
      channelBinding: 'Enabled'
    }
  }
}

// --- Outputs ---

@description('Resource ID of the managed domain.')
output oId string = rDomain.id
