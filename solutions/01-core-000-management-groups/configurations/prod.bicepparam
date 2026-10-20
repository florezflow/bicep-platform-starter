using 'br/platform:solutions/01-core-000-management-groups:v1.0.0'

var vSubscriptions = loadJsonContent('../../../platform.json').environments.prod.subscriptions

param pRoot = {
  id: 'contoso'
  displayName: 'Contoso'
}

param pPlacements = [
  { group: 'platform-connectivity', subscriptionId: vSubscriptions.connectivity }
  { group: 'platform-identity', subscriptionId: vSubscriptions.identity }
  { group: 'platform-management', subscriptionId: vSubscriptions.management }
  { group: 'platform-security', subscriptionId: vSubscriptions.security }
  { group: 'landingzones-corp', subscriptionId: vSubscriptions.sampleApp }
]
