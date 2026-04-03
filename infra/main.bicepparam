using 'main.bicep'

param location = 'westus2'
param sqlAdminUser = 'sqladmin'
param sqlAdminPassword = readEnvironmentVariable('SQL_ADMIN_PASSWORD', '')
param prefix = 'zava'
param alertEmail = ''
