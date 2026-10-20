using 'br/platform:solutions/02-workloads-000-sample-app:v1.1.0'

var vSubscriptions = loadJsonContent('../../../platform.json').environments.dev.subscriptions

param pContext = {
  environment: 'dev'
  location: 'switzerlandnorth'
  tags: {
    workload: 'sample-app'
    owner: 'app-team'
  }
}

param pHub = {
  subscriptionId: vSubscriptions.connectivity
  resourceGroupName: 'rg-hub-dev-szn-001'
  name: 'vnet-hub-dev-szn-001'
}

param pAddressPrefix = '10.20.16.0/24'

param pContainers = ['uploads']

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
