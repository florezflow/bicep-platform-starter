using 'br/platform:solutions/02-workloads-000-sample-app:v1.0.0'

var vSubscriptions = loadJsonContent('../../../platform.json').environments.prod.subscriptions

param pContext = {
  environment: 'prod'
  location: 'switzerlandnorth'
  tags: {
    workload: 'sample-app'
    owner: 'app-team'
  }
}

param pHub = {
  subscriptionId: vSubscriptions.connectivity
  resourceGroupName: 'rg-hub-prod-szn-001'
  name: 'vnet-hub-prod-szn-001'
}

param pAddressPrefix = '10.10.16.0/24'

param pSecurityRules = [
  {
    name: 'allow-https-from-vnet'
    priority: 200
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationPortRange: '443'
  }
]
