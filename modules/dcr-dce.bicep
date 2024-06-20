param location string
param vmName string
param LawId string
param LawName string
param suffix string
// param AMPLS object

resource DCEWindows 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: 'dce-ampls-${suffix}'
  location: location
  kind: 'Windows'
  properties: {
    configurationAccess: {}
    // description: 'string'
    // immutableId: 'string'
    logsIngestion: {}
    networkAcls: {
      publicNetworkAccess: 'Disabled'
    }
  }
}

// DCRの作成
resource DCRWindows 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'dcr-ampls-${suffix}-win'
  location: location
  kind: 'Windows'
  properties: {
    dataCollectionEndpointId: DCEWindows.id
    dataFlows: [
      {
        streams: [
          'Microsoft-InsightsMetrics'
        ]
        destinations: [
          'azureMonitorMetrics-default'
        ]
        transformKql: 'source'
        outputStream: 'Microsoft-InsightsMetrics'
      }
      {
        streams: [
          'Microsoft-Event'
        ]
        destinations: [
          LawName
        ]
        transformKql: 'source'
        outputStream: 'Microsoft-Event'
      }
    ]
    dataSources: {
      performanceCounters: [
        {
          counterSpecifiers: [
            'perfCount60s'
          ]
          name: 'string'
          samplingFrequencyInSeconds:60 
          streams: [
            'Microsoft-InsightsMetrics'
          ]
        }
      ]
      windowsEventLogs: [
        {
          name: 'WindowsEventLog'
          streams: [
            'Microsoft-Event'
          ]
          xPathQueries: [
            'Application!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0 or Level=5)]]'
            'Security!*[System[(band(Keywords,13510798882111488))]]'
            'System!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0 or Level=5)]]'
          ]
        }
      ]
    }
    // description: 'string'
    destinations: {
      azureMonitorMetrics: {
        name: 'azureMonitorMetrics-default'
      }
      logAnalytics: [
        {
          name: LawName
          workspaceResourceId: LawId
        }
      ]
    }
    streamDeclarations: {}
  }
}

// To set the resource scope, get the existing resource
// or set the scope as resourceGroup()
resource windowsVM 'Microsoft.Compute/virtualMachines@2023-03-01' existing = {
  name: vmName
}

resource DCRAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'configurationDCR'
  // scope: resourceGroup()
  scope: windowsVM
  properties: {
    // dataCollectionEndpointId: DCEWindows.id
    dataCollectionRuleId: DCRWindows.id
    // description: ''
  }
}

resource DCEAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'configurationAccessEndpoint'
  scope: windowsVM
  properties: {
    dataCollectionEndpointId: DCEWindows.id
    // dataCollectionRuleId: DCRWindows.id
    // description: ''
  }
}

output DCEWindowsId string = DCEWindows.id
output DCRWindowsId string = DCRWindows.id
