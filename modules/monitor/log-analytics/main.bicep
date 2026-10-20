metadata name = 'Log Analytics workspace'
metadata description = 'A Log Analytics workspace that accepts Entra ID authentication only.'
metadata version = '1.0.0'

import { contextType, resourceName } from 'br/platform:types:v1.0.0'

// --- Parameters ---

@description('Where the workspace is deployed.')
param pContext contextType

@description('Purpose of the workspace, used in its name.')
@metadata({ example: 'management' })
param pName string

@description('Days the workspace keeps its data.')
@minValue(30)
@maxValue(730)
param pRetentionInDays int = 90

// --- Resources ---

resource rWorkspace 'Microsoft.OperationalInsights/workspaces@2026-03-01' = {
  name: resourceName('log', pName, pContext, 1)
  location: pContext.location
  tags: pContext.?tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: pRetentionInDays
    features: {
      disableLocalAuth: true
    }
  }
}

// --- Outputs ---

@description('Name of the workspace.')
output oName string = rWorkspace.name

@description('Resource ID of the workspace.')
output oId string = rWorkspace.id
