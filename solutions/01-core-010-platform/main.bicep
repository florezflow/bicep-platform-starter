metadata name = 'Platform'
metadata description = 'Deployment 2 of an environment: connectivity, identity, management and security, each in its own subscription. Deploys at the platform management group, after the management groups exist.'
metadata version = '1.0.0'

targetScope = 'managementGroup'

import { contextType, domainServicesType, hubVnetType, platformSubscriptionsType } from 'br/platform:types:v1.0.0'

// --- Parameters ---

@description('Where the platform is deployed.')
param pContext contextType

@description('The four platform subscriptions.')
param pSubscriptions platformSubscriptionsType

@description('Address space of the hub.')
@metadata({ example: '10.10.0.0/22' })
param pHubAddressPrefix string

@description('Address space of the identity spoke.')
@metadata({ example: '10.10.4.0/24' })
param pIdentityAddressPrefix string

@description('The managed domain. Leave it out where the tenant already has one: a tenant can have only one.')
param pDomainServices domainServicesType?

@description('DNS servers of the identity spoke. Once the managed domain runs, its two IP addresses.')
@metadata({ example: ['10.10.4.4', '10.10.4.5'] })
param pDnsServers string[] = []

// --- Modules ---

module mConnectivity 'br/platform:modules/platform/connectivity:v1.0.0' = {
  scope: subscription(pSubscriptions.connectivity)
  params: {
    pContext: pContext
    pAddressPrefix: pHubAddressPrefix
  }
}

module mManagement 'br/platform:modules/platform/management:v1.0.0' = {
  scope: subscription(pSubscriptions.management)
  params: {
    pContext: pContext
  }
}

module mSecurity 'br/platform:modules/platform/security:v1.0.0' = {
  scope: subscription(pSubscriptions.security)
  params: {
    pContext: pContext
  }
}

module mIdentity 'br/platform:modules/platform/identity:v1.0.0' = {
  scope: subscription(pSubscriptions.identity)
  params: {
    pContext: pContext
    pAddressPrefix: pIdentityAddressPrefix
    pHub: mConnectivity.outputs.oHub
    pDomainServices: pDomainServices
    pDnsServers: pDnsServers
  }
}

// --- Outputs ---

@description('The hub, for the workloads that peer with it.')
output oHub hubVnetType = mConnectivity.outputs.oHub

@description('Resource ID of the platform Log Analytics workspace.')
output oManagementWorkspaceId string = mManagement.outputs.oWorkspaceId

@description('Resource ID of the Sentinel workspace.')
output oSecurityWorkspaceId string = mSecurity.outputs.oWorkspaceId
