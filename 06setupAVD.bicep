@description('Location for all resources.')
param location string = resourceGroup().location

@description('Name of the AVD Host Pool')
param hostPoolName string = 'avd-hostpool'

@description('Host Pool friendly name')
param hostPoolFriendlyName string = 'AVD Host Pool'

@description('Host Pool description')
param hostPoolDescription string = 'Azure Virtual Desktop Host Pool'

@description('AVD desktop application group name')
param desktopAppGroupName string = 'avd-desktop-app-group'

@description('AVD desktop application group friendly name')
param desktopAppGroupFriendlyName string = 'Desktop Application Group'

@description('AVD desktop application group description')
param desktopAppGroupDescription string = 'Desktop Application Group for AVD'

@description('AVD workspace name')
param workspaceName string = 'avd-workspace'

@description('AVD workspace friendly name')
param workspaceFriendlyName string = 'AVD Workspace'

@description('AVD workspace description')
param workspaceDescription string = 'Azure Virtual Desktop Workspace'

@description('Maximum session limit')
param maxSessionLimit int = 10

@description('Host Pool type')
@allowed([
  'Personal'
  'Pooled'
])
param hostPoolType string = 'Pooled'

@description('Load balancing algorithm for Pooled Host Pool')
@allowed([
  'BreadthFirst'
  'DepthFirst'
])
param loadBalancerType string = 'DepthFirst'

@description('Host Pool token validity start time')
param tokenValidityStartTime string = utcNow('u')

@description('Host Pool token validity end time - in hours from start time')
param tokenValidityLength string = 'PT8H'

// Host Pool resource
resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2022-09-09' = {
  name: hostPoolName
  location: location
  properties: {
    friendlyName: hostPoolFriendlyName
    description: hostPoolDescription
    hostPoolType: hostPoolType
    maxSessionLimit: maxSessionLimit
    loadBalancerType: loadBalancerType
    validationEnvironment: false
    preferredAppGroupType: 'Desktop'
    registrationInfo: {
      expirationTime: dateTimeAdd(tokenValidityStartTime, tokenValidityLength)
      token: null
      registrationTokenOperation: 'Update'
    }
  }
}

// Desktop Application Group
resource applicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2022-09-09' = {
  name: desktopAppGroupName
  location: location
  properties: {
    friendlyName: desktopAppGroupFriendlyName
    description: desktopAppGroupDescription
    applicationGroupType: 'Desktop'
    hostPoolArmPath: hostPool.id
  }
}

// AVD Workspace
resource workspace 'Microsoft.DesktopVirtualization/workspaces@2022-09-09' = {
  name: workspaceName
  location: location
  properties: {
    friendlyName: workspaceFriendlyName
    description: workspaceDescription
    applicationGroupReferences: [
      applicationGroup.id
    ]
  }
}

// Outputs
output hostPoolName string = hostPool.name
output hostPoolId string = hostPool.id
output applicationGroupName string = applicationGroup.name
output applicationGroupId string = applicationGroup.id
output workspaceName string = workspace.name
output workspaceId string = workspace.id
