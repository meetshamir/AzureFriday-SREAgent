// ──────────────────────────────────────────────────────────────
//  Zava — Azure Friday SRE Agent Demo Lab
//  Infrastructure-as-Code (Bicep)
//
//  Deploys: SQL Server + DB, Log Analytics, App Insights,
//           App Service Plan, 3 Web Apps, Alert Rules, Dashboard
// ──────────────────────────────────────────────────────────────

targetScope = 'resourceGroup'

// ── Parameters ──────────────────────────────────────────────

@description('Azure region for all resources')
param location string = 'westus2'

@description('SQL Server administrator username')
param sqlAdminUser string = 'CloudSAe816d324'

@secure()
@description('SQL Server administrator password')
param sqlAdminPassword string

@description('Naming prefix for all resources')
param prefix string = 'zava'

@description('Alert notification email address')
param alertEmail string = ''

// ── Variables ───────────────────────────────────────────────

var sqlServerName = 'sql-${prefix}'
var sqlDatabaseName = 'sqldb-${prefix}'
var lawName = 'law-${prefix}'
var appInsightsName = 'ai-${prefix}'
var aspName = 'asp-${prefix}'
var appName = 'app-${prefix}'
var itPortalName = 'app-${prefix}-itportal'
var warrantyAppName = 'app-${prefix}-warranty'
var dashboardName = 'dash-${prefix}'

// ── 1. SQL Server ───────────────────────────────────────────

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminUser
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    publicNetworkAccess: 'Enabled'
  }
}

// ── 2. SQL Database (Basic 5 DTU) ───────────────────────────

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648 // 2 GB
  }
}

// ── 3. SQL Firewall Rule (Allow Azure Services) ─────────────

resource sqlFirewallAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// ── 4. Log Analytics Workspace ──────────────────────────────

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ── 5. Application Insights ────────────────────────────────

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ── 6. App Service Plan (B1 Linux) ──────────────────────────

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: aspName
  location: location
  kind: 'linux'
  sku: {
    name: 'B1'
    tier: 'Basic'
    capacity: 1
  }
  properties: {
    reserved: true // required for Linux
  }
}

// ── 7. Web App — Main App (.NET 8) ──────────────────────────

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|8.0'
      alwaysOn: true
      healthCheckPath: '/health'
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
      ]
      connectionStrings: [
        {
          name: 'DefaultConnection'
          connectionString: 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${sqlDatabaseName};User ID=${sqlAdminUser};Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=False;'
          type: 'SQLAzure'
        }
      ]
    }
  }
}

// ── 8. Web App — IT Portal (Node 20) ────────────────────────

resource itPortal 'Microsoft.Web/sites@2023-12-01' = {
  name: itPortalName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      alwaysOn: true
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~20'
        }
      ]
    }
  }
}

// ── 9. Web App — Warranty API (Python 3.12) ─────────────────

resource warrantyApp 'Microsoft.Web/sites@2023-12-01' = {
  name: warrantyAppName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.12'
      alwaysOn: true
      appCommandLine: 'uvicorn app:app --host 0.0.0.0 --port 8000'
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
      ]
    }
  }
}

// ── 10. Action Group for Alerts ─────────────────────────────

resource actionGroup 'Microsoft.Insights/actionGroups@2023-09-01-preview' = if (!empty(alertEmail)) {
  name: 'ag-${prefix}-sre'
  location: 'global'
  properties: {
    groupShortName: '${prefix}SRE'
    enabled: true
    emailReceivers: [
      {
        name: 'SRE Team'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// ── 10a. Alert: SQL DTU > 80% ───────────────────────────────

resource alertDtu 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-${prefix}-dtu-high'
  location: 'global'
  properties: {
    description: 'SQL Database DTU usage exceeds 80%'
    severity: 2
    enabled: true
    scopes: [
      sqlDatabase.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighDTU'
          metricName: 'dtu_consumption_percent'
          metricNamespace: 'Microsoft.Sql/servers/databases'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: !empty(alertEmail) ? [
      {
        actionGroupId: actionGroup.id
      }
    ] : []
  }
}

// ── 10b. Alert: HTTP 5xx Errors ─────────────────────────────

resource alertHttp5xx 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-${prefix}-http-5xx'
  location: 'global'
  properties: {
    description: 'App Service returning HTTP 5xx errors'
    severity: 1
    enabled: true
    scopes: [
      webApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Http5xx'
          metricName: 'Http5xx'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: !empty(alertEmail) ? [
      {
        actionGroupId: actionGroup.id
      }
    ] : []
  }
}

// ── 10c. Alert: Health Check Failures ───────────────────────

resource alertHealthCheck 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-${prefix}-health-check'
  location: 'global'
  properties: {
    description: 'App Service health check failing'
    severity: 1
    enabled: true
    scopes: [
      webApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HealthCheckFailure'
          metricName: 'HealthCheckStatus'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'LessThan'
          threshold: 100
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: !empty(alertEmail) ? [
      {
        actionGroupId: actionGroup.id
      }
    ] : []
  }
}

// ── 11. Azure Portal Dashboard ──────────────────────────────

resource dashboard 'Microsoft.Portal/dashboards@2020-09-01-preview' = {
  name: dashboardName
  location: location
  tags: {
    'hidden-title': 'Zava Operations Dashboard'
  }
  properties: {
    lenses: [
      {
        order: 0
        parts: [
          {
            position: { x: 0, y: 0, colSpan: 16, rowSpan: 2 }
            metadata: {
              type: 'Extension/HubsExtension/PartType/MarkdownPart'
              inputs: []
              settings: {
                content: {
                  content: '## Zava Operations Dashboard\n**Real-time monitoring** for SQL Database, App Service, and Application Insights.\n\n_Resource Group:_ `${resourceGroup().name}` | _Region:_ `${location}`'
                  title: 'Zava Operations Dashboard'
                  subtitle: 'Enterprise Monitoring'
                  markdownSource: 1
                }
              }
            }
          }
          {
            position: { x: 0, y: 2, colSpan: 8, rowSpan: 4 }
            metadata: {
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              inputs: [
                {
                  name: 'options'
                  value: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: { id: sqlDatabase.id }
                          name: 'dtu_consumption_percent'
                          aggregationType: 4 // Average
                          namespace: 'Microsoft.Sql/servers/databases'
                          metricVisualization: { displayName: 'DTU percentage' }
                        }
                      ]
                      title: 'SQL Database — DTU Usage'
                      visualization: { chartType: 2 }
                    }
                  }
                }
              ]
              settings: {}
            }
          }
          {
            position: { x: 8, y: 2, colSpan: 8, rowSpan: 4 }
            metadata: {
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              inputs: [
                {
                  name: 'options'
                  value: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: { id: webApp.id }
                          name: 'HttpResponseTime'
                          aggregationType: 4
                          namespace: 'Microsoft.Web/sites'
                          metricVisualization: { displayName: 'Response Time' }
                        }
                      ]
                      title: 'App Service — Response Time'
                      visualization: { chartType: 2 }
                    }
                  }
                }
              ]
              settings: {}
            }
          }
          {
            position: { x: 0, y: 6, colSpan: 8, rowSpan: 4 }
            metadata: {
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              inputs: [
                {
                  name: 'options'
                  value: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: { id: webApp.id }
                          name: 'Http5xx'
                          aggregationType: 1 // Total
                          namespace: 'Microsoft.Web/sites'
                          metricVisualization: { displayName: 'HTTP 5xx Errors' }
                        }
                      ]
                      title: 'App Service — HTTP 5xx Errors'
                      visualization: { chartType: 2 }
                    }
                  }
                }
              ]
              settings: {}
            }
          }
          {
            position: { x: 8, y: 6, colSpan: 8, rowSpan: 4 }
            metadata: {
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              inputs: [
                {
                  name: 'options'
                  value: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: { id: webApp.id }
                          name: 'HealthCheckStatus'
                          aggregationType: 4
                          namespace: 'Microsoft.Web/sites'
                          metricVisualization: { displayName: 'Health Check Status' }
                        }
                      ]
                      title: 'App Service — Health Check'
                      visualization: { chartType: 2 }
                    }
                  }
                }
              ]
              settings: {}
            }
          }
        ]
      }
    ]
  }
}

// ── Outputs ─────────────────────────────────────────────────

output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = sqlDatabaseName
output appUrl string = 'https://${webApp.properties.defaultHostName}'
output itPortalUrl string = 'https://${itPortal.properties.defaultHostName}'
output warrantyApiUrl string = 'https://${warrantyApp.properties.defaultHostName}'
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output logAnalyticsWorkspaceId string = logAnalytics.properties.customerId
output sqlConnectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${sqlDatabaseName};User ID=${sqlAdminUser};Password=<your-password>;Encrypt=True;TrustServerCertificate=False;'
