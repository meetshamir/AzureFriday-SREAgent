# Azure Friday — SRE Agent Demo Lab

**Complete lab for demonstrating Azure SRE Agent capabilities with Scott Hanselman**

> Deploy a realistic e-commerce platform ("Zava — Intelligent Athletic Apparel"), break it on purpose, and watch Azure SRE Agent detect, diagnose, and remediate issues autonomously.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Azure Resource Group (rg-zava)                │
│                                                                        │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐               │
│  │  app-zava     │   │ app-zava-    │   │ app-zava-    │               │
│  │  (.NET 8)     │   │ itportal     │   │ warranty     │               │
│  │  Main API     │   │ (Node 20)    │   │ (Python 3.12)│               │
│  │  /health      │   │ IT Portal    │   │ FastAPI      │               │
│  │  /api/products│   │              │   │ /warranty/*  │               │
│  └──────┬───────┘   └──────────────┘   └──────────────┘               │
│         │                                                              │
│         ▼                                                              │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐               │
│  │  sql-zava     │   │  law-zava    │   │  ai-zava     │               │
│  │  SQL Server   │   │  Log         │   │  Application │               │
│  │  ┌──────────┐ │   │  Analytics   │   │  Insights    │               │
│  │  │sqldb-zava│ │   │  Workspace   │   │              │               │
│  │  │ Basic 5  │ │   └──────────────┘   └──────────────┘               │
│  │  │ DTU      │ │                                                     │
│  │  └──────────┘ │   ┌──────────────────────────────────┐              │
│  └──────────────┘   │  Azure Monitor Alert Rules        │              │
│                      │  • DTU > 80%                      │              │
│                      │  • HTTP 5xx errors                │              │
│                      │  • Health check failures          │              │
│                      └──────────────────────────────────┘              │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    ▼                ▼                ▼
           ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
           │  SRE Agent 1 │ │  SRE Agent 2 │ │  ServiceNow  │
           │  SQL & App   │ │  IT Support  │ │  PDI          │
           │  Performance │ │  & SNOW      │ │  (Incidents)  │
           │              │ │              │ │               │
           │  MCP:        │ │  MCP:        │ └──────────────┘
           │  • mssql-mcp │ │  • (none)    │
           │  • github-mcp│ │              │
           └──────────────┘ └──────────────┘

           ┌──────────────────────────────────────────┐
           │         Demo Simulator (Python)          │
           │  simulator/demo.py                       │
           │  Triggers scenarios 1-5 via SQL & HTTP   │
           └──────────────────────────────────────────┘
```

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| **Azure subscription** | — | [Free account](https://azure.microsoft.com/free/) |
| **Azure CLI** | 2.60+ | `winget install Microsoft.AzureCLI` |
| **.NET SDK** | 8.0+ | `winget install Microsoft.DotNet.SDK.8` |
| **Python** | 3.11+ | `winget install Python.Python.3.12` |
| **Node.js** | 18+ | `winget install OpenJS.NodeJS.LTS` |
| **srectl CLI** | latest | [Install docs](https://learn.microsoft.com/azure/sre-agent) |
| **ServiceNow PDI** | — | [Free instance](https://developer.servicenow.com/) |

> **Optional:** SQL Server Management Studio (SSMS) or Azure Data Studio for database inspection.

---

## Quick Start (5 minutes)

```bash
# 1. Clone the repo
git clone https://github.com/meetshamir/AzureFriday-SREAgent.git
cd AzureFriday-SREAgent

# 2. Log into Azure
az login

# 3. Deploy everything with one command
./infra/deploy.ps1 -ResourceGroup rg-zava -Location westus2 -SqlPassword 'YourP@ssw0rd!'

# — OR deploy step-by-step: —

# Create resource group
az group create -n rg-zava -l westus2

# Deploy infrastructure
az deployment group create \
  -g rg-zava \
  -f infra/main.bicep \
  -p sqlAdminPassword='YourP@ssw0rd!'

# Seed the database
sqlcmd -S sql-zava.database.windows.net -U CloudSAe816d324 \
       -P 'YourP@ssw0rd!' -d sqldb-zava -i infra/seed-database.sql
```

After deployment, verify:

```bash
curl https://app-zava.azurewebsites.net/health
# → {"status":"healthy","database":"connected"}

curl https://app-zava.azurewebsites.net/api/products
# → [{"id":1,"name":"Zava UltraBoost Running Shoe",...}, ...]

curl https://app-zava-warranty.azurewebsites.net/health
# → {"status":"healthy"}
```

---

## Project Structure

```
AzureFriday-SREAgent/
├── infra/                          # Infrastructure-as-Code
│   ├── main.bicep                  # All Azure resources (SQL, Apps, Monitoring)
│   ├── main.bicepparam             # Default parameter values
│   ├── deploy.ps1                  # One-click deployment script
│   └── seed-database.sql           # Products, Orders, OrderItems seed data
│
├── src/                            # Main .NET 8 API (Zava storefront)
│   ├── Program.cs                  # Minimal API: /health, /api/products
│   ├── AzureFridayApp.csproj       # .NET project (SQL Client, App Insights)
│   └── appsettings.json            # Connection string config
│
├── laptop-request-site/            # IT Portal (Node.js static site)
│   ├── index.html                  # Laptop request form
│   ├── server.js                   # Simple HTTP file server
│   ├── style.css                   # Portal styling
│   └── package.json                # Node project
│
├── warranty-tool/                  # Warranty Lookup API (Python FastAPI)
│   ├── app.py                      # FastAPI app: /warranty/{serial}, /devices
│   ├── check_warranty.py           # Standalone CLI tool for SRE Agent
│   ├── requirements.txt            # fastapi, uvicorn, gunicorn
│   └── startup.sh                  # App Service startup command
│
├── simulator/                      # Demo scenario simulator
│   ├── demo.py                     # Interactive CLI with 5 scenarios
│   └── requirements.txt            # rich, requests, pymssql
│
├── sre-config/                     # SRE Agent configuration (srectl)
│   ├── agent1/                     # SQL & App Performance Agent
│   │   ├── agents/
│   │   │   ├── deployment-validator/       # Post-deploy health checks
│   │   │   └── sql-performance-investigator/ # SQL perf analysis
│   │   ├── hooks/
│   │   │   ├── change-risk-assessor.yaml   # Assess risk before changes
│   │   │   └── sql-write-guard.yaml        # Guard SQL write operations
│   │   ├── skills/
│   │   │   ├── sql-blocking-diagnosis/     # Diagnose blocking chains
│   │   │   ├── sql-blocking-fix/           # Resolve blocking chains
│   │   │   ├── sql-performance-fix/        # Fix slow queries (indexes)
│   │   │   └── sql-query-diagnosis/        # Identify slow queries
│   │   ├── tools/
│   │   │   └── AssessChangeRisk/           # Risk assessment tool
│   │   └── scheduledtasks/
│   │       └── weekly-cost-report/         # Weekly cost analysis
│   │
│   └── agent2/                     # IT Support & ServiceNow Agent
│       ├── agents/
│       │   └── it-support-handler/         # Handle IT support requests
│       └── tools/
│           ├── CheckWarranty/              # Warranty lookup tool
│           └── LookupServiceNowIncident/   # ServiceNow integration
│
├── dashboard.json                  # Azure Portal dashboard template
├── .github/workflows/deploy.yml    # CI/CD pipeline with SRE Agent trigger
└── .gitignore
```

---

## Demo Scenarios

### Scenario 1: Slow Query (Missing Index)

| | |
|---|---|
| **What it demonstrates** | SRE Agent detects a performance degradation caused by a missing database index, diagnoses the root cause, and creates the index autonomously |
| **SRE Agent features** | Azure Monitor alert → Agent activation, SQL MCP connector, `sql-query-diagnosis` skill, `sql-performance-fix` skill, `change-risk-assessor` hook, `sql-write-guard` hook |

**Setup:**
1. Ensure the database has the Products table populated (via `seed-database.sql`)
2. DTU alert rule is configured (deployed automatically by Bicep)
3. SRE Agent 1 has the SQL MCP connector with the database connection string

**How to trigger:**
```bash
python simulator/demo.py
# Select option 1: "Slow Query (Missing Index)"
```

The simulator drops any existing indexes on the `Products.Category` column, then fires rapid `SELECT ... WHERE Category = @cat` queries in a loop, driving DTU usage above 80%.

**What to expect:**
1. The simulator shows live query latency (typically 800–2000ms per query)
2. Azure Monitor fires the DTU > 80% alert (~2-5 minutes)
3. SRE Agent 1 activates, connects via SQL MCP, identifies the missing index
4. The `change-risk-assessor` hook evaluates the proposed `CREATE INDEX` statement
5. The `sql-write-guard` hook approves the DDL change
6. SRE Agent creates the index: `CREATE NONCLUSTERED INDEX IX_Products_Category ON Products(Category)`
7. The simulator detects the index and shows a before/after performance graph
8. Query latency drops from ~1000ms to ~5ms (99%+ improvement)

---

### Scenario 2: Blocking Chain

| | |
|---|---|
| **What it demonstrates** | SRE Agent detects and resolves a SQL blocking chain (transaction deadlock) |
| **SRE Agent features** | `sql-blocking-diagnosis` skill, `sql-blocking-fix` skill, SQL MCP |

**Setup:**
- Same SQL MCP setup as Scenario 1

**How to trigger:**
```bash
python simulator/demo.py
# Select option 2: "Blocking Chain"
```

The simulator opens a long-running transaction that holds locks on the Orders table, then fires concurrent queries that get blocked.

**What to expect:**
1. The simulator opens a transaction with `BEGIN TRAN` + `UPDATE Orders` + `WAITFOR DELAY`
2. Subsequent queries to the Orders table are blocked
3. SRE Agent detects the blocking chain via `sys.dm_exec_requests` and `sys.dm_tran_locks`
4. Agent identifies the blocking session and either kills it or waits for it to complete
5. Blocked queries resume execution

---

### Scenario 3: Bad Deployment

| | |
|---|---|
| **What it demonstrates** | SRE Agent validates a deployment post-push and investigates failures |
| **SRE Agent features** | GitHub Actions HTTP trigger, `deployment-validator` extended agent, GitHub MCP connector, health endpoint monitoring |

**Setup:**
1. Configure the GitHub Actions workflow (`.github/workflows/deploy.yml`)
2. SRE Agent 1 must have an HTTP trigger configured
3. GitHub MCP connector must be set up with a PAT

**How to trigger:**

*Option A — Via GitHub Actions:*
```bash
# Trigger the workflow with force_failure=true
gh workflow run deploy.yml -f force_failure=true
```

*Option B — Via the simulator:*
```bash
python simulator/demo.py
# Select option 3: "Bad Deployment"
```

The simulator stops the app service, causing health checks to fail.

**What to expect:**
1. The deployment fails or the app health check returns HTTP 503
2. GitHub Actions sends an HTTP trigger to the SRE Agent with deployment metadata
3. The `deployment-validator` agent activates
4. Agent hits `/health`, sees the failure, and investigates via GitHub MCP
5. Agent checks the commit diff, identifies the issue, and reports findings
6. If the app was stopped, the agent restarts it and confirms health

---

### Scenario 4: ServiceNow Integration

| | |
|---|---|
| **What it demonstrates** | SRE Agent handles an IT support request by looking up warranty status and creating/updating ServiceNow incidents |
| **SRE Agent features** | `it-support-handler` extended agent, `CheckWarranty` tool, `LookupServiceNowIncident` tool, ServiceNow API integration |

**Setup:**
1. Create a ServiceNow Personal Developer Instance (PDI) at [developer.servicenow.com](https://developer.servicenow.com/)
2. Configure the ServiceNow URL, username, and password in the simulator env vars
3. SRE Agent 2 must have the `CheckWarranty` and `LookupServiceNowIncident` tools

**How to trigger:**
```bash
python simulator/demo.py
# Select option 4: "ServiceNow Integration"
```

The simulator creates a ServiceNow incident for a laptop warranty issue, then triggers SRE Agent 2.

**What to expect:**
1. The simulator creates an INC ticket in ServiceNow
2. SRE Agent 2 activates, looks up the incident via `LookupServiceNowIncident`
3. Agent calls `CheckWarranty` with the laptop serial number
4. The warranty API returns status (active/expired, replacement eligibility)
5. Agent updates the ServiceNow incident with warranty details and recommendation

---

### Scenario 5: Reset All

| | |
|---|---|
| **What it demonstrates** | Cleans up all demo scenarios — drops indexes, kills blocking sessions, restarts apps |

```bash
python simulator/demo.py
# Select option 5: "Reset All"
```

---

## SRE Agent Configuration

### Step 1: Create Agents at sre.azure.com

1. Navigate to [https://sre.azure.com](https://sre.azure.com)
2. Click **"Create Agent"**
3. Create **Agent 1 — SQL & App Performance:**
   - Name: `zava-sreagent-1`
   - Attach to resource group: `rg-zava`
   - Description: "Monitors SQL performance, handles deployments, manages app health"
4. Create **Agent 2 — IT Support & ServiceNow:**
   - Name: `zava-sreagent-2`
   - Attach to resource group: `rg-zava`
   - Description: "Handles IT support tickets, warranty lookups, ServiceNow integration"

### Step 2: Configure MCP Connectors

See [MCP Connector Setup](#mcp-connector-setup) below.

### Step 3: Apply Skills, Hooks, and Agents via srectl

```bash
# Install srectl (if not already installed)
# See https://learn.microsoft.com/azure/sre-agent for install instructions

# Select Agent 1 context
srectl config set-context <agent-1-id>

# Apply all Agent 1 configurations
srectl apply -f sre-config/agent1/skills/
srectl apply -f sre-config/agent1/hooks/
srectl apply -f sre-config/agent1/agents/
srectl apply -f sre-config/agent1/tools/
srectl apply -f sre-config/agent1/scheduledtasks/

# Switch to Agent 2
srectl config set-context <agent-2-id>

# Apply Agent 2 configurations
srectl apply -f sre-config/agent2/agents/
srectl apply -f sre-config/agent2/tools/
```

### Step 4: Set Up Incident Handlers and HTTP Triggers

**HTTP Trigger (for GitHub Actions):**
1. In the SRE Agent portal, go to Agent 1 → Triggers
2. Create a new HTTP trigger
3. Copy the trigger URL into `.github/workflows/deploy.yml` (line 79)

**Alert Handler (for Azure Monitor):**
1. In the SRE Agent portal, go to Agent 1 → Alert Handlers
2. Link the DTU, HTTP 5xx, and Health Check alert rules
3. SRE Agent will automatically activate when these alerts fire

---

## MCP Connector Setup

### SQL MCP Connector (Agent 1)

The SQL MCP connector allows SRE Agent to query and modify the SQL database.

1. In SRE Agent portal → Agent 1 → Tools → Add MCP Connector
2. Package: `mssql-mcp@latest`
3. Environment variables:

| Variable | Value |
|----------|-------|
| `MSSQL_CONNECTION_STRING` | `Server=tcp:sql-zava.database.windows.net,1433;Database=sqldb-zava;User ID=CloudSAe816d324;Password=<your-password>;Encrypt=True;TrustServerCertificate=False;` |

### GitHub MCP Connector (Agent 1)

The GitHub MCP connector allows SRE Agent to inspect repositories, commits, and pull requests.

1. Create a GitHub Personal Access Token (PAT):
   - Go to [github.com/settings/tokens](https://github.com/settings/tokens)
   - Create a fine-grained token with `repo` read access to your fork
2. In SRE Agent portal → Agent 1 → Tools → Add MCP Connector
3. Package: `@github/github-mcp-server`
4. Environment variables:

| Variable | Value |
|----------|-------|
| `GITHUB_PERSONAL_ACCESS_TOKEN` | `ghp_xxxxxxxxxxxxxxxxxxxx` |

---

## ServiceNow PDI Setup

### Get a Free Instance

1. Go to [developer.servicenow.com](https://developer.servicenow.com/)
2. Sign up for a free account
3. Click **"Start Building"** → **"Request Instance"**
4. Wait for the instance to provision (typically 5–10 minutes)
5. Note your instance URL (e.g., `https://dev123456.service-now.com`)

### Configure for the Demo

Set environment variables before running the simulator:

```powershell
$env:ZAVA_SN_URL  = "https://dev123456.service-now.com"
$env:ZAVA_SN_USER = "admin"
$env:ZAVA_SN_PASS = "your-instance-password"
```

### Create Test Tickets

The simulator (Scenario 4) creates incidents automatically. To create them manually:

1. Log into your ServiceNow instance
2. Navigate to **Incident → Create New**
3. Fill in:
   - Short Description: `Laptop replacement request — warranty expired`
   - Category: `Hardware`
   - Urgency: `Medium`
   - Description: `Employee SN-2021-DEL-3344 laptop warranty has expired. Requesting replacement.`

---

## Simulator Usage

```bash
# Install dependencies
pip install -r simulator/requirements.txt

# Run interactive menu
python simulator/demo.py

# Direct scenario launch
python simulator/demo.py 1    # Slow Query (Missing Index)
python simulator/demo.py 2    # Blocking Chain
python simulator/demo.py 3    # Bad Deployment
python simulator/demo.py 4    # ServiceNow Integration
python simulator/demo.py 5    # Reset All
```

### Environment Variables

Override defaults by setting environment variables:

```powershell
$env:ZAVA_SQL_SERVER   = "sql-zava.database.windows.net"
$env:ZAVA_SQL_DATABASE = "sqldb-zava"
$env:ZAVA_SQL_USER     = "CloudSAe816d324"
$env:ZAVA_SQL_PASSWORD = "YourP@ssw0rd!"
$env:ZAVA_APP_URL      = "https://app-zava.azurewebsites.net"
$env:ZAVA_SN_URL       = "https://dev123456.service-now.com"
$env:ZAVA_SN_USER      = "admin"
$env:ZAVA_SN_PASS      = "your-password"
```

---

## Resource Links

After deployment, bookmark these:

| Resource | URL |
|----------|-----|
| **Main App** | `https://app-zava.azurewebsites.net` |
| **IT Portal** | `https://app-zava-itportal.azurewebsites.net` |
| **Warranty API** | `https://app-zava-warranty.azurewebsites.net` |
| **Azure Portal** | `https://portal.azure.com` → resource group `rg-zava` |
| **SRE Agent Portal** | `https://sre.azure.com` |
| **Dashboard** | Azure Portal → search "Zava Operations Dashboard" |
| **App Insights** | Azure Portal → `ai-zava` |
| **SQL Database** | Azure Portal → `sql-zava` / `sqldb-zava` |

---

## Troubleshooting

### MCP Connection Issues

**Problem:** SRE Agent can't connect to SQL via MCP.

- Verify the connection string in the MCP connector environment variables
- Ensure the SQL firewall rule allows Azure services (`0.0.0.0`)
- Test the connection manually:
  ```bash
  sqlcmd -S sql-zava.database.windows.net -U CloudSAe816d324 -P 'password' -d sqldb-zava -Q "SELECT 1"
  ```

**Problem:** GitHub MCP connector fails.

- Verify the PAT hasn't expired
- Ensure the PAT has `repo` read permissions
- Test: `curl -H "Authorization: token ghp_xxx" https://api.github.com/user`

### SQL Auth vs Entra Auth

The Bicep template configures **SQL authentication** (username/password) for simplicity. The `appsettings.json` in the source code references **Managed Identity** auth — the deployment script overrides this with the SQL connection string via App Service settings.

If you prefer Entra (AAD) auth:
1. Enable Entra admin on the SQL server
2. Assign a managed identity to the App Service
3. Update the connection string to use `Authentication=Active Directory Managed Identity`

### App Service Quota

**Problem:** `Conflict: Cannot create more than N App Service plans in region.`

- Free/shared tier App Service plans have quota limits per region
- Delete unused App Service plans, or use a different region
- The B1 plan supports up to 3 apps (all 3 Zava apps share one plan)

### Alert Not Firing

**Problem:** DTU alert doesn't fire during Scenario 1.

- The Basic 5 DTU tier has very low headroom — alerts typically fire within 2–5 minutes
- Check Azure Monitor → Alerts → look for "alert-zava-dtu-high"
- Verify the alert rule is enabled: Azure Portal → Alerts → Alert Rules
- If the simulator queries complete too fast, the DTU spike may be insufficient. Run the simulator longer.
- Check the evaluation window: the alert uses a 5-minute window with 1-minute frequency

### Simulator Can't Connect to SQL

- Install `pymssql`: `pip install pymssql`
- Ensure your client IP is in the SQL firewall rules:
  ```bash
  az sql server firewall-rule create -g rg-zava -s sql-zava \
    -n MyIP --start-ip-address <your-ip> --end-ip-address <your-ip>
  ```

---

## Cost Estimate

All resources use the lowest production-capable SKUs:

| Resource | SKU | Monthly Cost |
|----------|-----|-------------|
| SQL Database | Basic (5 DTU) | ~$5 |
| App Service Plan | B1 (shared by 3 apps) | ~$13 |
| Log Analytics | Pay-per-GB (free tier: 5GB) | ~$0 |
| Application Insights | Included with Log Analytics | ~$0 |
| Azure Monitor Alerts | Free tier (10 alert rules) | ~$0 |
| **Total** | | **~$18/month** |

> 💡 **Tip:** Delete the resource group when not in use to stop all charges:
> ```bash
> az group delete -n rg-zava --yes --no-wait
> ```

---

## License

This project is for demonstration purposes as part of Azure Friday.
