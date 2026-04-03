using 'main.bicep'

param location = 'westus2'
param sqlAdminUser = 'CloudSAe816d324'
param sqlAdminPassword = readEnvironmentVariable('SQL_ADMIN_PASSWORD', '')
param prefix = 'zava'
param alertEmail = ''
