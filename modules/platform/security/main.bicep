metadata name = 'Platform: security'
metadata description = 'Microsoft Sentinel on its own Log Analytics workspace, apart from the platform logs.'
metadata version = '1.0.0'

targetScope = 'subscription'

import { contextType, resourceName } from 'br/platform:types:v1.0.0'

// --- Parameters ---

@description('Where the security resources are deployed.')
param pContext contextType

@description('Days the workspace keeps security logs.')
@minValue(30)
@maxValue(730)
param pRetentionInDays int = 365

// --- Resources ---

resource rRg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceName('rg', 'security', pContext, 1)
  location: pContext.location
  tags: pContext.?tags
}

// --- Modules ---

module mWorkspace 'br/platform:modules/monitor/log-analytics:v1.0.0' = {
  scope: rRg
  params: {
    pContext: pContext
    pName: 'security'
    pRetentionInDays: pRetentionInDays
  }
}

module mSentinel 'br/platform:modules/security/sentinel:v1.0.0' = {
  scope: rRg
  params: {
    pWorkspaceName: mWorkspace.outputs.oName
  }
}

// --- Outputs ---

@description('Resource ID of the security workspace.')
output oWorkspaceId string = mWorkspace.outputs.oId
