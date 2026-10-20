using 'br/platform:solutions/01-core-010-platform:v1.0.0'

var vSubscriptions = loadJsonContent('../../../platform.json').environments.dev.subscriptions

param pContext = {
  environment: 'dev'
  location: 'switzerlandnorth'
  tags: {
    workload: 'platform'
    owner: 'platform-team'
  }
}

param pSubscriptions = {
  connectivity: vSubscriptions.connectivity
  identity: vSubscriptions.identity
  management: vSubscriptions.management
  security: vSubscriptions.security
}

param pHubAddressPrefix = '10.20.0.0/22'
param pIdentityAddressPrefix = '10.20.4.0/24'

// No pDomainServices: a tenant can have only one managed domain, and prod has it
