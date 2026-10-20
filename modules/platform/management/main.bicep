metadata name = 'Platform: management'
metadata description = 'The Log Analytics workspace for platform logs and monitoring.'
metadata version = '1.0.0'

targetScope = 'subscription'

import { contextType, resourceName } from 'br/platform:types:v1.0.0'

// --- Parameters ---

@description('Where the management resources are deployed.')
param pContext contextType

@description('Days the workspace keeps platform logs.')
@minValue(30)
@maxValue(730)
param pRetentionInDays int = 90

// --- Resources ---

resource rRg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceName('rg', 'management', pContext, 1)
  location: pContext.location
  tags: pContext.?tags
}

// --- Modules ---

module mWorkspace 'br/platform:modules/monitor/log-analytics:v1.0.0' = {
  scope: rRg
  params: {
    pContext: pContext
    pName: 'management'
    pRetentionInDays: pRetentionInDays
  }
}

// --- Outputs ---

@description('Resource ID of the platform workspace.')
output oWorkspaceId string = mWorkspace.outputs.oId
