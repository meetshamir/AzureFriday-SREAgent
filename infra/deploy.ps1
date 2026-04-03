<#
.SYNOPSIS
    Deploys the Zava Azure Friday SRE Agent demo lab to Azure.

.DESCRIPTION
    1. Creates the resource group
    2. Deploys the Bicep template (SQL, App Service, monitoring)
    3. Seeds the SQL database with Products, Orders, OrderItems
    4. Deploys the 3 web apps (main .NET app, IT portal, warranty API)
    5. Sets connection strings and app settings
    6. Outputs SRE Agent setup instructions

.PARAMETER ResourceGroup
    Name of the Azure resource group. Default: rg-zava

.PARAMETER Location
    Azure region. Default: westus2

.PARAMETER Prefix
    Naming prefix for all resources. Default: zava

.PARAMETER SqlPassword
    SQL admin password. Will prompt if not provided.

.PARAMETER AlertEmail
    Optional email for Azure Monitor alert notifications.

.PARAMETER SkipInfra
    Skip Bicep deployment (useful when re-deploying apps only).

.PARAMETER SkipSeed
    Skip database seeding.

.PARAMETER SkipApps
    Skip web app deployment.

.EXAMPLE
    .\deploy.ps1 -ResourceGroup rg-zava -Location westus2 -SqlPassword 'MyP@ss123!'

.EXAMPLE
    .\deploy.ps1 -SkipInfra -SkipSeed   # Re-deploy apps only
#>

[CmdletBinding()]
param(
    [string]$ResourceGroup = 'rg-zava',
    [string]$Location      = 'westus2',
    [string]$Prefix        = 'zava',
    [string]$SqlPassword,
    [string]$AlertEmail    = '',
    [switch]$SkipInfra,
    [switch]$SkipSeed,
    [switch]$SkipApps
)

$ErrorActionPreference = 'Stop'
$InfraDir = $PSScriptRoot
$RepoRoot = Split-Path $InfraDir -Parent

# ── Helpers ──────────────────────────────────────────────────

function Write-Step { param([string]$Msg) Write-Host "`n▶ $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "  ✅ $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  ⚠️  $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "  ❌ $Msg" -ForegroundColor Red }

# ── Pre-checks ───────────────────────────────────────────────

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║   Zava — Azure Friday SRE Agent Demo Lab Deployer      ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

if (-not $SqlPassword) {
    $SqlPassword = Read-Host -Prompt "Enter SQL admin password" -AsSecureString |
        ForEach-Object { [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($_)) }
}

# Verify Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Err "Azure CLI (az) not found. Install from https://aka.ms/installazurecli"
    exit 1
}

$SqlAdminUser = 'CloudSAe816d324'
$SqlServer    = "sql-$Prefix"
$SqlDatabase  = "sqldb-$Prefix"
$AppName      = "app-$Prefix"
$ItPortalName = "app-$Prefix-itportal"
$WarrantyName = "app-$Prefix-warranty"

# ═════════════════════════════════════════════════════════════
#  STEP 1 — Infrastructure
# ═════════════════════════════════════════════════════════════

if (-not $SkipInfra) {
    Write-Step "Creating resource group: $ResourceGroup in $Location"
    az group create --name $ResourceGroup --location $Location --output none
    Write-Ok "Resource group ready"

    Write-Step "Deploying Bicep template (this may take 3-5 minutes)..."
    $deployResult = az deployment group create `
        --resource-group $ResourceGroup `
        --template-file "$InfraDir\main.bicep" `
        --parameters prefix=$Prefix `
                     sqlAdminUser=$SqlAdminUser `
                     sqlAdminPassword=$SqlPassword `
                     location=$Location `
                     alertEmail=$AlertEmail `
        --output json | ConvertFrom-Json

    if ($LASTEXITCODE -ne 0) {
        Write-Err "Bicep deployment failed"
        exit 1
    }

    $outputs = $deployResult.properties.outputs
    Write-Ok "Infrastructure deployed"
    Write-Host "     App URL:        $($outputs.appUrl.value)"
    Write-Host "     IT Portal URL:  $($outputs.itPortalUrl.value)"
    Write-Host "     Warranty URL:   $($outputs.warrantyApiUrl.value)"
    Write-Host "     SQL Server:     $($outputs.sqlServerFqdn.value)"
} else {
    Write-Warn "Skipping infrastructure deployment (--SkipInfra)"
}

# ═════════════════════════════════════════════════════════════
#  STEP 2 — Seed Database
# ═════════════════════════════════════════════════════════════

if (-not $SkipSeed) {
    Write-Step "Seeding SQL database..."

    # Add client IP to firewall
    $clientIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10)
    Write-Host "     Adding firewall rule for client IP: $clientIp"
    az sql server firewall-rule create `
        --resource-group $ResourceGroup `
        --server $SqlServer `
        --name "DeployClient" `
        --start-ip-address $clientIp `
        --end-ip-address $clientIp `
        --output none 2>$null

    # Run seed script via sqlcmd
    $sqlFqdn = "$SqlServer.database.windows.net"
    $seedFile = "$InfraDir\seed-database.sql"

    if (Get-Command sqlcmd -ErrorAction SilentlyContinue) {
        sqlcmd -S $sqlFqdn -U $SqlAdminUser -P $SqlPassword -d $SqlDatabase -i $seedFile -b
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Database seeded successfully"
        } else {
            Write-Err "sqlcmd failed. You can seed manually: sqlcmd -S $sqlFqdn -U $SqlAdminUser -d $SqlDatabase -i $seedFile"
        }
    } else {
        Write-Warn "sqlcmd not found. Trying az sql command..."
        # Read and execute SQL via az
        $sqlContent = Get-Content $seedFile -Raw
        # Split on GO statements and run each batch
        $batches = $sqlContent -split '\r?\nGO\r?\n'
        foreach ($batch in $batches) {
            $batch = $batch.Trim()
            if ($batch -and $batch -notmatch '^\s*$') {
                try {
                    Invoke-Sqlcmd -ServerInstance $sqlFqdn -Database $SqlDatabase `
                        -Username $SqlAdminUser -Password $SqlPassword `
                        -Query $batch -ErrorAction Stop 2>$null
                } catch {
                    Write-Warn "Run seed-database.sql manually using SSMS or Azure Data Studio"
                    Write-Host "     Connection: $sqlFqdn | DB: $SqlDatabase | User: $SqlAdminUser"
                    break
                }
            }
        }
        Write-Ok "Database seed attempted"
    }

    # Clean up firewall rule
    az sql server firewall-rule delete `
        --resource-group $ResourceGroup `
        --server $SqlServer `
        --name "DeployClient" `
        --output none 2>$null
} else {
    Write-Warn "Skipping database seed (--SkipSeed)"
}

# ═════════════════════════════════════════════════════════════
#  STEP 3 — Deploy Web Apps
# ═════════════════════════════════════════════════════════════

if (-not $SkipApps) {

    # ── 3a. Main .NET App ────────────────────────────────────
    Write-Step "Publishing & deploying main app ($AppName)..."
    $publishDir = "$RepoRoot\publish-main"
    $zipPath    = "$RepoRoot\publish-main.zip"

    dotnet publish "$RepoRoot\src\AzureFridayApp.csproj" `
        --configuration Release `
        --output $publishDir `
        --verbosity quiet

    if ($LASTEXITCODE -ne 0) {
        Write-Err "dotnet publish failed"
        exit 1
    }

    # Create zip
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path "$publishDir\*" -DestinationPath $zipPath -Force

    az webapp deploy --resource-group $ResourceGroup --name $AppName `
        --src-path $zipPath --type zip --output none
    Write-Ok "Main app deployed: https://$AppName.azurewebsites.net"

    # Clean up
    Remove-Item $publishDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

    # ── 3b. IT Portal (Node) ─────────────────────────────────
    Write-Step "Deploying IT portal ($ItPortalName)..."
    $itPortalDir = "$RepoRoot\laptop-request-site"
    $itZipPath   = "$RepoRoot\publish-itportal.zip"

    if (Test-Path $itZipPath) { Remove-Item $itZipPath -Force }
    Compress-Archive -Path "$itPortalDir\*" -DestinationPath $itZipPath -Force

    az webapp deploy --resource-group $ResourceGroup --name $ItPortalName `
        --src-path $itZipPath --type zip --output none
    Write-Ok "IT Portal deployed: https://$ItPortalName.azurewebsites.net"

    Remove-Item $itZipPath -Force -ErrorAction SilentlyContinue

    # ── 3c. Warranty API (Python) ────────────────────────────
    Write-Step "Deploying warranty API ($WarrantyName)..."
    $warrantyDir  = "$RepoRoot\warranty-tool"
    $warZipPath   = "$RepoRoot\publish-warranty.zip"

    if (Test-Path $warZipPath) { Remove-Item $warZipPath -Force }
    Compress-Archive -Path "$warrantyDir\*" -DestinationPath $warZipPath -Force

    az webapp deploy --resource-group $ResourceGroup --name $WarrantyName `
        --src-path $warZipPath --type zip --output none
    Write-Ok "Warranty API deployed: https://$WarrantyName.azurewebsites.net"

    Remove-Item $warZipPath -Force -ErrorAction SilentlyContinue

} else {
    Write-Warn "Skipping app deployment (--SkipApps)"
}

# ═════════════════════════════════════════════════════════════
#  STEP 4 — SRE Agent Setup Instructions
# ═════════════════════════════════════════════════════════════

Write-Step "SRE Agent setup"
Write-Host ""
Write-Host "  ┌──────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
Write-Host "  │  SRE Agent configuration must be done via sre.azure.com │" -ForegroundColor Yellow
Write-Host "  └──────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. Go to https://sre.azure.com and create two SRE Agents:" -ForegroundColor White
Write-Host "     • Agent 1: SQL & App Performance (attach to rg-$Prefix)" -ForegroundColor Gray
Write-Host "     • Agent 2: IT Support & ServiceNow (attach to rg-$Prefix)" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Add MCP connectors in the SRE Agent portal:" -ForegroundColor White
Write-Host "     • SQL MCP:    mssql-mcp@latest" -ForegroundColor Gray
Write-Host "       Env vars:   MSSQL_CONNECTION_STRING" -ForegroundColor DarkGray
Write-Host "     • GitHub MCP: @github/github-mcp-server" -ForegroundColor Gray
Write-Host "       Env vars:   GITHUB_PERSONAL_ACCESS_TOKEN" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  3. Apply srectl configs:" -ForegroundColor White
Write-Host "     srectl apply -f sre-config/agent1/skills/" -ForegroundColor Gray
Write-Host "     srectl apply -f sre-config/agent1/hooks/" -ForegroundColor Gray
Write-Host "     srectl apply -f sre-config/agent1/agents/" -ForegroundColor Gray
Write-Host "     srectl apply -f sre-config/agent1/tools/" -ForegroundColor Gray
Write-Host "     srectl apply -f sre-config/agent1/scheduledtasks/" -ForegroundColor Gray
Write-Host "     srectl apply -f sre-config/agent2/agents/" -ForegroundColor Gray
Write-Host "     srectl apply -f sre-config/agent2/tools/" -ForegroundColor Gray
Write-Host ""

# ═════════════════════════════════════════════════════════════
#  DONE
# ═════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   ✅  Deployment Complete!                              ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Resources:" -ForegroundColor White
Write-Host "    Main App:      https://$AppName.azurewebsites.net" -ForegroundColor Gray
Write-Host "    IT Portal:     https://$ItPortalName.azurewebsites.net" -ForegroundColor Gray
Write-Host "    Warranty API:  https://$WarrantyName.azurewebsites.net" -ForegroundColor Gray
Write-Host "    SQL Server:    $SqlServer.database.windows.net" -ForegroundColor Gray
Write-Host "    Dashboard:     https://portal.azure.com (search 'dash-$Prefix')" -ForegroundColor Gray
Write-Host ""
Write-Host "  Next Steps:" -ForegroundColor White
Write-Host "    1. Configure SRE Agents at https://sre.azure.com" -ForegroundColor Gray
Write-Host "    2. Run the simulator:  python simulator/demo.py" -ForegroundColor Gray
Write-Host "    3. Trigger scenarios and watch SRE Agent respond!" -ForegroundColor Gray
Write-Host ""
