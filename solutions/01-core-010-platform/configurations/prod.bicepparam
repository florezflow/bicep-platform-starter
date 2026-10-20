using 'br/platform:solutions/01-core-010-platform:v1.0.0'

var vSubscriptions = loadJsonContent('../../../platform.json').environments.prod.subscriptions

param pContext = {
  environment: 'prod'
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

param pHubAddressPrefix = '10.10.0.0/22'
param pIdentityAddressPrefix = '10.10.4.0/24'

param pDomainServices = {
  domainName: 'aaddscontoso.com'
  sku: 'Standard'
  notifyEmails: ['platform-team@contoso.com']
}

// Once the managed domain runs: its two IP addresses, here and in every spoke that joins the domain
param pDnsServers = []
