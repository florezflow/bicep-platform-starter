metadata name = 'Shared types'
metadata description = 'User-defined types and naming functions that every module and solution imports, so one object has one shape and one resource has one name pattern across the repo.'
metadata version = '1.0.0'

// --- Types ---

@export()
@description('Environment short name. Each environment has its own management group hierarchy and subscriptions.')
type environmentType = 'dev' | 'prod'

@export()
@description('Azure regions this platform deploys to. Each one has a short code in regionCode().')
type regionType = 'switzerlandnorth' | 'switzerlandwest' | 'westeurope'

@export()
@description('Where a resource is deployed. Every module takes it as pContext.')
type contextType = {
  @description('Environment short name, used in every resource name.')
  environment: environmentType

  @description('Azure region of the resources.')
  location: regionType

  @description('Tags added to every resource.')
  @metadata({ example: { workload: 'sample-app', owner: 'platform-team' } })
  tags: object?
}

@export()
@description('The hub virtual network a spoke peers with. The platform stack owns it; a spoke only references it.')
type hubVnetType = {
  @description('Subscription of the hub.')
  subscriptionId: string

  @description('Resource group of the hub.')
  @metadata({ example: 'rg-hub-prod-szn-001' })
  resourceGroupName: string

  @description('Name of the hub virtual network.')
  @metadata({ example: 'vnet-hub-prod-szn-001' })
  name: string
}

@export()
@description('One rule of a network security group.')
type securityRuleType = {
  @description('Rule name.')
  @metadata({ example: 'allow-https-from-vnet' })
  name: string

  @description('Priority between 100 and 4096. Lower runs first.')
  @minValue(100)
  @maxValue(4096)
  priority: int

  @description('Traffic direction.')
  direction: 'Inbound' | 'Outbound'

  @description('Allow or deny the traffic.')
  access: 'Allow' | 'Deny'

  @description('Network protocol.')
  protocol: 'Tcp' | 'Udp' | '*'

  @description('Source address prefix or service tag.')
  @metadata({ example: 'VirtualNetwork' })
  sourceAddressPrefix: string

  @description('Destination port or range.')
  @metadata({ example: '443' })
  destinationPortRange: string
}

@export()
@description('Storage account redundancy.')
type storageSkuType = 'Standard_LRS' | 'Standard_ZRS' | 'Standard_GZRS'

@export()
@description('Management groups of the hierarchy, named relative to its root.')
type managementGroupKeyType =
  | 'platform-connectivity'
  | 'platform-identity'
  | 'platform-management'
  | 'platform-security'
  | 'landingzones-corp'
  | 'landingzones-online'
  | 'sandbox'
  | 'decommissioned'

@export()
@description('A subscription and the management group it belongs in.')
type subscriptionPlacementType = {
  @description('Management group, relative to the root of the hierarchy.')
  @metadata({ example: 'landingzones-corp' })
  group: managementGroupKeyType

  @description('Subscription to place there.')
  subscriptionId: string
}

@export()
@description('The four platform subscriptions of an environment.')
type platformSubscriptionsType = {
  @description('Hub network and private DNS.')
  connectivity: string

  @description('Microsoft Entra Domain Services.')
  identity: string

  @description('Log Analytics for the platform.')
  management: string

  @description('Microsoft Sentinel.')
  security: string
}

@export()
@description('A Microsoft Entra Domain Services managed domain. A tenant can have only one.')
type domainServicesType = {
  @description('DNS name of the managed domain. Use a domain you own.')
  @metadata({ example: 'aaddscontoso.com' })
  domainName: string

  @description('Size of the managed domain.')
  sku: 'Standard' | 'Enterprise' | 'Premium'

  @description('Email addresses notified about alerts on the managed domain, on top of the domain admins.')
  @metadata({ example: ['platform-team@contoso.com'] })
  notifyEmails: string[]?
}

// --- Functions ---

@export()
@description('Short code of an Azure region, used in resource names.')
func regionCode(location regionType) string =>
  {
    switzerlandnorth: 'szn'
    switzerlandwest: 'szw'
    westeurope: 'weu'
  }[location]

@export()
@description('Resource name in the pattern <abbreviation>-<name>-<environment>-<region code>-<instance>.')
func resourceName(abbreviation string, name string, context contextType, instance int) string =>
  '${abbreviation}-${name}-${context.environment}-${regionCode(context.location)}-${padLeft(instance, 3, '0')}'
