param location string
param vmName string
param vmAdminUserName string
@secure()
param vmAdminPassword string
//RGの作成もBicepに含められる？
// param resourceGroupName string = '20230815-ampls-bicep'

param zones array = [
  'agentsvc.azure-automation.net'
  'blob.${environment().suffixes.storage}' // blob.core.windows.net
  'monitor.azure.com'
  'ods.opinsights.azure.com'
  'oms.opinsights.azure.com'
]

// 先にNSG作成
resource VNetCloudNSG 'Microsoft.Network/networkSecurityGroups@2019-11-01' = {
  name: 'vnet-cloud-nsg'
  location: location
  properties: {
    // securityRules: [
    //   {
    //     name: 'nsgRule'
    //     properties: {
    //       description: 'description'
    //       protocol: 'Tcp'
    //       sourcePortRange: '*'
    //       destinationPortRange: '*'
    //       sourceAddressPrefix: '*'
    //       destinationAddressPrefix: '*'
    //       access: 'Allow'
    //       priority: 100
    //       direction: 'Inbound'
    //     }
    //   }
    // ]
  }
}

resource VNetCloud 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: 'vnet-cloud'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-main'
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: VNetCloudNSG.id
          }
        }
      }
      {
        name: 'subnet-pe'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: VNetCloudNSG.id
          }
        }
      }
    ]
  }
 
  resource SubnetMain 'subnets' existing = {
    name: 'subnet-main'
  }
  resource SubnetPE 'subnets' existing = {
    name: 'subnet-pe'
  }
}

// Create Log Analytics Workspace
resource LawAmpls 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'law-01'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Azure Monitor Private Link Scope
resource AMPLS 'microsoft.insights/privateLinkScopes@2021-07-01-preview' = {
  name: 'ampls-01'
  location: 'global'
  properties: {
    accessModeSettings: {
      // exclusions: [
      //   {
      //     ingestionAccessMode: 'string'
      //     privateEndpointConnectionName: 'string'
      //     queryAccessMode: 'string'
      //   }
      // ]
      //あとでPrivate Onlyに直す
      ingestionAccessMode: 'Open'
      queryAccessMode: 'Open'
    }
  }
}

// Create Private Endpoint
resource PeAmpls 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: 'pe-ampls-01'
  location: location
  properties: {
    subnet: {
      id: VNetCloud::SubnetPE.id
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-ampls-01-connection'
        properties: {
          privateLinkServiceId: AMPLS.id
          groupIds: [
            //Azure PortalですでにデプロイされているLAWのJSONと比較
            'azuremonitor'
          ]
        }
      }
    ]
  }
}

resource DCEWindows 'Microsoft.Insights/dataCollectionEndpoints@2021-09-01-preview' = {
  name: 'dce-ampls'
  location: location
  kind: 'Windows'
  properties: {
    configurationAccess: {}
    // description: 'string'
    // immutableId: 'string'
    logsIngestion: {}
    networkAcls: {
      //あとでDisableにする
      publicNetworkAccess: 'Enabled'
    }
  }
}

// DCRの作成
resource DCRWindows 'Microsoft.Insights/dataCollectionRules@2021-09-01-preview' = {
  name: 'dcr-ampls'
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
          LawAmpls.name
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
          name: LawAmpls.name
          workspaceResourceId: LawAmpls.id
        }
      ]
    }
    streamDeclarations: {}
  }
}

// // VMの作成
// module CreateVM './modules/vm.bicep' = {
//   name: 'vm'
//   params: {
//     location: location
//     subnetId: VNetCloud::SubnetMain.id
//     vmName:vmName
//     vmAdminUserName: vmAdminUserName
//     vmAdminPassword: vmAdminPassword
//   }
// }

resource VMCloudNic 'Microsoft.Network/networkInterfaces@2020-11-01' = {
  name: 'vm-cloud-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: VNetCloud::SubnetMain.id
          }
        }
      }
    ]
  }
}


resource windowsVM 'Microsoft.Compute/virtualMachines@2020-12-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2ms'
    }
    osProfile: {
      computerName: vmName
      adminUsername: vmAdminUserName
      adminPassword: vmAdminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        name: 'vm-cloud-win-osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: VMCloudNic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: false
      }
    }
  }
}

// // CreateVMで作成したVMを参照
// // CreateVMへの明示的な依存関係が必要かも
// resource windowsVM 'Microsoft.Compute/virtualMachines@2021-07-01' existing = {
//  name: 'vm-cloud-win'
// }

//なぜかDCRの割り当てとDCEの割り当てを別で行う必要がある
resource DCRAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2021-09-01-preview' = {
  name: 'configurationDCR'
  scope: windowsVM
  properties: {
    // dataCollectionEndpointId: DCEWindows.id
    dataCollectionRuleId: DCRWindows.id
    // description: ''
  }
}

resource DCEAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2021-09-01-preview' = {
  name: 'configurationAccessEndpoint'
  scope: windowsVM
  properties: {
    dataCollectionEndpointId: DCEWindows.id
    // dataCollectionRuleId: DCRWindows.id
    // description: ''
  }
}

// private DNS Zoneの作成
// 繰り返しになるので zones は配列で定義
// https://blog.aimless.jp/archives/2022/07/use-integration-between-private-endpoint-and-private-dns-zone-in-bicep/#:~:text=Private%20Endpoint%20%E3%81%A8%20Private%20DNS%20Zone%20%E3%81%AE%E8%87%AA%E5%8B%95%E9%80%A3%E6%90%BA%E3%82%92%20Bicep,%E3%81%AE%E3%83%97%E3%83%A9%E3%82%A4%E3%83%99%E3%83%BC%E3%83%88%20IP%20%E3%82%A2%E3%83%89%E3%83%AC%E3%82%B9%E3%81%AB%E5%90%8D%E5%89%8D%E8%A7%A3%E6%B1%BA%E3%81%99%E3%82%8B%E5%BF%85%E8%A6%81%E3%81%8C%E3%81%82%E3%82%8A%E3%81%BE%E3%81%99%E3%80%82%20%E3%81%93%E3%81%AE%E5%90%8D%E5%89%8D%E8%A7%A3%E6%B1%BA%E3%82%92%E5%AE%9F%E7%8F%BE%E3%81%99%E3%82%8B%E3%81%9F%E3%82%81%E3%81%AE%E4%B8%80%E3%81%A4%E3%81%AE%E3%82%AA%E3%83%97%E3%82%B7%E3%83%A7%E3%83%B3%E3%81%8C%20Private%20DNS%20Zone%20%E3%81%A7%E3%81%99%E3%80%82
resource privateDnsZoneForAmpls 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zone in zones: {
  name: 'privatelink.${zone}'
  location: 'global'
  properties: {
  }
}]

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zone,i) in zones: { 
  parent: privateDnsZoneForAmpls[i]
  name: '${zone}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: VNetCloud.id
    }
  }
}]

// resource peDnsGroupForAmpls 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = [for (zone,i) in zones:{
//   parent: PeAmpls // 設定する Private Endpoint を Parenet で参照
//   name: 'pe-dns-group-${zone}'
//   properties: {
//     privateDnsZoneConfigs: [
//       {
//         name: privateDnsZoneForAmpls[i].name
//         properties: {
//           privateDnsZoneId: privateDnsZoneForAmpls[i].id
//         }
//       }
//     ]
//   }
// }]

//ここはLoopでかけそう
resource peDnsGroupForAmpls 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
  parent: PeAmpls
  name: 'pvtEndpointDnsGroupForAmpls'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: privateDnsZoneForAmpls[0].name
        properties: {
          privateDnsZoneId: privateDnsZoneForAmpls[0].id
        }
      }
      {
        name: privateDnsZoneForAmpls[1].name
        properties: {
          privateDnsZoneId: privateDnsZoneForAmpls[1].id
        }
      }
      {
        name: privateDnsZoneForAmpls[2].name
        properties: {
          privateDnsZoneId: privateDnsZoneForAmpls[2].id
        }
      }
      {
        name: privateDnsZoneForAmpls[3].name
        properties: {
          privateDnsZoneId: privateDnsZoneForAmpls[3].id
        }
      }
      {
        name: privateDnsZoneForAmpls[4].name
        properties: {
          privateDnsZoneId: privateDnsZoneForAmpls[4].id
        }
      }
    ]
  }
}

// //DCEとLAWをAMPLSに紐づける

resource AmplsScopedLaw 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  name: 'amplsScopedLaw'
  parent: AMPLS
  properties: {
    linkedResourceId: LawAmpls.id
  }
}

resource AmplsScopedDCE 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  name: 'amplsScopedDCE'
  parent: AMPLS
  properties: {
    linkedResourceId: DCEWindows.id
  }
  dependsOn:[
    AmplsScopedLaw
  ]
}
