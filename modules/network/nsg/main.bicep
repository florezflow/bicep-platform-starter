metadata name = 'Network security group'
metadata description = 'A network security group with its rules.'
metadata version = '1.0.0'

import { contextType, resourceName, securityRuleType } from 'br/platform:types:v1.0.0'

// --- Parameters ---

@description('Where the network security group is deployed.')
param pContext contextType

@description('Purpose of the network security group, used in its name. Usually the purpose of its subnet.')
@metadata({ example: 'app' })
param pName string

@description('Security rules. Without rules, only the Azure default rules apply.')
param pSecurityRules securityRuleType[] = []

// --- Resources ---

resource rNsg 'Microsoft.Network/networkSecurityGroups@2026-01-01' = {
  name: resourceName('nsg', pName, pContext, 1)
  location: pContext.location
  tags: pContext.?tags
  properties: {
    securityRules: [
      for rule in pSecurityRules: {
        name: rule.name
        properties: {
          priority: rule.priority
          direction: rule.direction
          access: rule.access
          protocol: rule.protocol
          sourceAddressPrefix: rule.sourceAddressPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: rule.destinationPortRange
        }
      }
    ]
  }
}

// --- Outputs ---

@description('Resource ID of the network security group.')
output oId string = rNsg.id
