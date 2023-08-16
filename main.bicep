param location string
param vmName string
param vmAdminUserName string
@secure()
param vmAdminPassword string

// Define private DNS zone name as array
param zones array = [
  'agentsvc.azure-automation.net'
  'blob.${environment().suffixes.storage}' // blob.core.windows.net
  'monitor.azure.com'
  'ods.opinsights.azure.com'
  'oms.opinsights.azure.com'
]

// Create Network Security Group before VNet to attach NSG to Subnet
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
// Create VNet
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
  name: 'law-ampls'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    publicNetworkAccessForIngestion:'Disabled'
    retentionInDays: 30
  }
}

// Azure Monitor Private Link Scope
resource AMPLS 'microsoft.insights/privateLinkScopes@2021-07-01-preview' = {
  name: 'ampls'
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
      ingestionAccessMode: 'PrivateOnly' // PrivateOnly, Open
      queryAccessMode: 'Open'
    }
  }
}

// Create Private Endpoint
resource PeAmpls 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: 'pe-ampls'
  location: location
  properties: {
    subnet: {
      id: VNetCloud::SubnetPE.id
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-ampls-connection'
        properties: {
          privateLinkServiceId: AMPLS.id
          groupIds: [
            'azuremonitor' // aquire this value from the existing private endpoint used for AMPLS
          ]
        }
      }
    ]
  }
}

// Call VM module
module CreateVM './modules/vm.bicep' = {
  name: 'vm'
  params: {
    location: location
    subnetId: VNetCloud::SubnetMain.id
    vmName: vmName
    vmAdminUserName: vmAdminUserName
    vmAdminPassword: vmAdminPassword
  }
}

// To execute "resource~existing" after "CreateVM" module, include process in the same module and use "dependsOn"
module DCRDCE './modules/DCRDCE.bicep' = {
  name: 'attachDcrDce'
  params: {
    location: location
    vmName: vmName
    LawName: LawAmpls.name
    LawId: LawAmpls.id
    // AMPLS: AMPLS
  }
  dependsOn:[
    CreateVM
  ]
}

// Create Scoped Resource
// Connect Log Analytics Workspace to AMPLS
resource AmplsScopedLaw 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  name: 'amplsScopedLaw'
  parent: AMPLS
  properties: {
    linkedResourceId: LawAmpls.id
  }
}

// Connect Data Collection Endpoint to AMPLS
resource AmplsScopedDCE 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  name: 'amplsScopedDCE'
  parent: AMPLS
  properties: {
    linkedResourceId: DCRDCE.outputs.DCEWindowsId
  }
  dependsOn:[
    AmplsScopedLaw
  ]
}

// Create Private DNS Zone
// Define zone name as array
// https://blog.aimless.jp/archives/2022/07/use-integration-between-private-endpoint-and-private-dns-zone-in-bicep/#:~:text=Private%20Endpoint%20%E3%81%A8%20Private%20DNS%20Zone%20%E3%81%AE%E8%87%AA%E5%8B%95%E9%80%A3%E6%90%BA%E3%82%92%20Bicep,%E3%81%AE%E3%83%97%E3%83%A9%E3%82%A4%E3%83%99%E3%83%BC%E3%83%88%20IP%20%E3%82%A2%E3%83%89%E3%83%AC%E3%82%B9%E3%81%AB%E5%90%8D%E5%89%8D%E8%A7%A3%E6%B1%BA%E3%81%99%E3%82%8B%E5%BF%85%E8%A6%81%E3%81%8C%E3%81%82%E3%82%8A%E3%81%BE%E3%81%99%E3%80%82%20%E3%81%93%E3%81%AE%E5%90%8D%E5%89%8D%E8%A7%A3%E6%B1%BA%E3%82%92%E5%AE%9F%E7%8F%BE%E3%81%99%E3%82%8B%E3%81%9F%E3%82%81%E3%81%AE%E4%B8%80%E3%81%A4%E3%81%AE%E3%82%AA%E3%83%97%E3%82%B7%E3%83%A7%E3%83%B3%E3%81%8C%20Private%20DNS%20Zone%20%E3%81%A7%E3%81%99%E3%80%82
resource privateDnsZoneForAmpls 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zone in zones: {
  name: 'privatelink.${zone}'
  location: 'global'
  properties: {
  }
}]

// Connect Private DNS Zone to VNet
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

resource peDnsGroupForAmpls 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
  parent: PeAmpls
  name: 'pvtEndpointDnsGroupForAmpls'
  properties: {
    privateDnsZoneConfigs: [
      for (zone,i) in zones: {
        name: privateDnsZoneForAmpls[i].name
        properties: {
          privateDnsZoneId: privateDnsZoneForAmpls[i].id
        }
      }
    ]
  }
}

// // Cannot create more than one private dns zone groups in the private endpoint pe-ampls
// // so name doesn't cantain loop variable = unique name
// // by incremental deploy, privateDnsZoneConfigs will be added during loop
// // VSCode: Unique resource or deployment name is required when looping. The loop item variable "zone" or the index variable "i" must be referenced in at least one of the value expressions of the following properties in the loop body: "name", "parent"
// resource peDnsGroupForAmpls 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = [for (zone,i) in zones:{
//   parent: PeAmpls
//   name: 'peDnsGp'
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

// // Rewrite with Loop structure? -> "privateDnsZoneLink" is not a loopable resource and bicep array cannot use append/add function
// resource peDnsGroupForAmpls 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
//   parent: PeAmpls
//   name: 'pvtEndpointDnsGroupForAmpls'
//   properties: {
//     privateDnsZoneConfigs: [
//       {
//         name: privateDnsZoneForAmpls[0].name
//         properties: {
//           privateDnsZoneId: privateDnsZoneForAmpls[0].id
//         }
//       }
//       {
//         name: privateDnsZoneForAmpls[1].name
//         properties: {
//           privateDnsZoneId: privateDnsZoneForAmpls[1].id
//         }
//       }
//       {
//         name: privateDnsZoneForAmpls[2].name
//         properties: {
//           privateDnsZoneId: privateDnsZoneForAmpls[2].id
//         }
//       }
//       {
//         name: privateDnsZoneForAmpls[3].name
//         properties: {
//           privateDnsZoneId: privateDnsZoneForAmpls[3].id
//         }
//       }
//       {
//         name: privateDnsZoneForAmpls[4].name
//         properties: {
//           privateDnsZoneId: privateDnsZoneForAmpls[4].id
//         }
//       }
//     ]
//   }
// }

// resource peDnsGroupForAmpls 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
//   parent: PeAmpls
//   name: 'pvtEndpointDnsGroupForAmpls'
//   properties: {
//     privateDnsZoneConfigs: [
//       for index in range(0,indexOf(zones,last(zones))): {
//         name: privateDnsZoneForAmpls[index].name
//         properties: {
//           privateDnsZoneId: privateDnsZoneForAmpls[index].id
//         }
//       }
//     ]
//   }
// }





