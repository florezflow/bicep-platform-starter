metadata name = 'Microsoft Sentinel'
metadata description = 'Turns on Microsoft Sentinel for an existing Log Analytics workspace.'
metadata version = '1.0.0'

// --- Parameters ---

@description('Name of the existing workspace, in the resource group this module deploys to.')
@metadata({ example: 'log-security-prod-szn-001' })
param pWorkspaceName string

// --- Resources ---

resource rWorkspace 'Microsoft.OperationalInsights/workspaces@2026-03-01' existing = {
  name: pWorkspaceName
}

resource rOnboarding 'Microsoft.SecurityInsights/onboardingStates@2025-09-01' = {
  scope: rWorkspace
  name: 'default'
  properties: {}
}

// --- Outputs ---

@description('Resource ID of the Sentinel onboarding.')
output oId string = rOnboarding.id
