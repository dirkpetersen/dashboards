# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project creates a simple web dashboard to monitor daily AWS Bedrock usage across all IAM users in an AWS account.

## Common Development Tasks

### Running the Application

```bash
# Install dependencies (if needed)
pip install -r requirements.txt

# Run the dashboard locally (default port 5000)
cd bedrock-usage
../.venv/bin/python app.py

# Run on a different port
../.venv/bin/python app.py --port 8080
```

### Testing the Application

When making changes to the application, follow these test procedures:

#### Manual Testing Procedure

1. **Launch the Flask server on an available port** (5001 or higher):
   ```bash
   cd bedrock-usage
   ../.venv/bin/python app.py --port 5001
   ```

2. **Test the API endpoint returns valid data**:
   ```bash
   curl -s http://localhost:5001/api/usage | python3 -m json.tool | head -50
   ```

3. **Verify high-utilization user data** (should include user `peterdir` with significant usage):
   ```bash
   curl -s http://localhost:5001/api/usage | python3 -c "
   import sys, json
   data = json.load(sys.stdin)
   print('User Invocations:', json.dumps(data.get('user_invocations', {}), indent=2))
   print('\nUser Costs:', json.dumps(data.get('user_costs', {}), indent=2))
   "
   ```

4. **Expected test case validation**:
   - Response should return valid JSON without errors
   - `user_invocations` should show multiple users including `peterdir`
   - `peterdir` should have high utilization (typically the highest or among the top users)
   - `user_costs` should show dollar amounts for each user
   - No Flask errors in the server console output

#### Test Case Requirements

When testing changes to the dashboard:
- **High-utilization test user**: `peterdir` should be present in results with significant invocations and costs
- **Multi-user validation**: Verify aggregation works correctly across multiple IAM users
- **Model diversity**: Check that multiple Claude model variants appear in results
- **Cost calculations**: Ensure costs are non-zero and calculated correctly based on token usage

#### Common Test Scenarios

**Scenario 1: Testing after code changes**
```bash
# Stop any running instance
pkill -f "python app.py"

# Start server on port 5001
cd bedrock-usage
../.venv/bin/python app.py --port 5001 &

# Wait for startup
sleep 3

# Run validation
curl -s http://localhost:5001/api/usage | python3 -m json.tool | grep -A 5 '"user_invocations"'
```

**Scenario 2: Performance testing**
```bash
# Time the API response
time curl -s http://localhost:5001/api/usage?days=7 > /dev/null

# Should complete in < 10 seconds with CloudWatch Logs Insights optimization
```

**Scenario 3: Testing different date ranges**
```bash
# Test 1 day
curl -s "http://localhost:5001/api/usage?days=1" | python3 -m json.tool | head -20

# Test 30 days
curl -s "http://localhost:5001/api/usage?days=30" | python3 -m json.tool | head -20
```

### Code Structure Overview

The application follows a straightforward Flask architecture:

- **app.py**: Main Flask application (~820 lines)
  - `get_config()`: Loads environment variables with dashboard-specific override support
  - `check_subnet_access()`: Middleware for VPN/subnet access control
  - `normalize_username()`: User aggregation logic (removes `bedrock-` prefix, applies `USER_MAP`)
  - `get_bedrock_usage()`: Core logic that fetches CloudWatch Logs using **CloudWatch Logs Insights queries** (10-100x faster than filter_log_events)
  - `_process_logs_insights_results()`: Processes aggregated query results from CloudWatch
  - Route handlers: `index()` (HTML dashboard), `usage_api()` (JSON data), `pricing_page()` (pricing table)
  - `BEDROCK_PRICING`: Hardcoded model pricing dictionary (update when AWS pricing changes)
  - Query caching infrastructure (`_query_cache`, `_cache_ttl`) for improved performance

- **HTML Templates**: Chart.js-based visualizations
  - `bedrock-usage-template.html`: Main dashboard with charts and tables
  - `bedrock-usage-template-pricing.html`: Model pricing reference table
  - `bedrock-usage-matrix.html`: Cost matrix showing dollars per user/model (with region prefixes stripped)

### Key Implementation Details

**Data Flow** (Optimized with CloudWatch Logs Insights):
1. On page load, frontend calls `/usage_api` endpoint
2. Backend initiates CloudWatch Logs Insights query on `/aws/bedrock/modelinvocations` log group
3. CloudWatch performs server-side aggregation (grouping by IAM user and model ID)
4. Backend receives pre-aggregated results and applies pricing calculations
5. Returns JSON with aggregated data and time-series trends

**Performance Optimization**:
- Uses CloudWatch Logs Insights for server-side aggregation (10-100x faster)
- Old approach: Fetch all events → aggregate in Python (slow for large datasets)
- New approach: CloudWatch aggregates → return only summary data (fast)
- Query caching infrastructure ready for future use (10-minute TTL)
- Optimized parsing with model prefix caching to avoid redundant operations

**User Aggregation**:
- Configure `USER_MAP` dictionary in `app.py` to map multiple user identities to one logical user
- Example: `'aider': 'peterdir'` aggregates "aider" invocations under "peterdir"
- Bedrock IAM role names have `bedrock-` prefix automatically removed

**Pricing Model**:
- `BEDROCK_PRICING` dictionary uses model IDs as keys (e.g., `'anthropic.claude-sonnet-4-5-20250929-v1:0'`)
- Prices are in USD per Million tokens, separate for input/output
- Region prefixes (us., global., eu., ap.) are automatically stripped during lookup and display
- Unknown models default to zero cost with a warning logged

**Cost Matrix** (User vs Model):
- Access at `/matrix` endpoint to view a spreadsheet-style breakdown
- Shows costs in dollars for each user-model combination
- Region prefixes automatically stripped (e.g., `us.anthropic.claude-3-5-sonnet...` displays as `anthropic.claude-3-5-sonnet...`)
- Includes row totals (user costs) and column totals (model costs)
- Color-coded cells: red for high cost, yellow for medium, green for low
- Supports filtering by date range (7, 30, 90 days)

### Common Modifications

**Adding a new model to pricing**:
- Add entry to `BEDROCK_PRICING` dict in `app.py` with model ID and input/output costs per million tokens
- Also add to `INACTIVE_BEDROCK_PRICING` if you want to preserve history

**Adding user aggregation**:
- Search for `USER_MAP = {}` in `app.py`
- Add entries like `'source_username': 'target_username'` to combine multiple identities
- Changes take effect on next dashboard page load

**Adjusting date range**:
- Modify `get_bedrock_usage(days=7)` function call in the route handler (default is 7 days)
- Also adjust the JavaScript `date_range` calculations in the HTML templates if needed

**Debugging CloudWatch queries**:
- Add debug prints in `get_bedrock_usage()` to log the CloudWatch filter expression and response
- Use `print()` statements since Flask debug mode captures stdout
- Check CloudWatch Logs console directly for `/aws/bedrock/modelinvocations` log group

## Architecture

Flask application with enhanced analytics that:
1. Serves a web dashboard at `http://localhost:5000`
2. Fetches Bedrock usage data from CloudWatch Logs via boto3
3. Tracks invocations, token usage (input/output), and costs per user and model
4. Displays interactive visualizations with Chart.js
5. No database required - fetches fresh data on each page load

## Key AWS APIs

- **CloudWatch Logs Insights**: `logs:StartQuery` and `logs:GetQueryResults` to query Bedrock invocation logs with server-side aggregation
  - Log group: `/aws/bedrock/modelinvocations`
  - Contains per-invocation details including IAM user identity, model ID, and token counts
  - Uses Insights queries for 10-100x faster performance than filtering
- **Cost Explorer**: `ce:GetCostAndUsage` for cost data by user (optional, not currently used)
- **CloudWatch Metrics**: `cloudwatch:GetMetricStatistics` for invocation counts (optional, not currently used)

## AWS Permissions Required

The IAM user/role running this needs:
- `logs:StartQuery` (required for CloudWatch Logs Insights)
- `logs:GetQueryResults` (required for CloudWatch Logs Insights)
- `logs:DescribeLogStreams` (optional, for troubleshooting)
- `cloudwatch:GetMetricStatistics` (optional, for future enhancements)
- `cloudwatch:ListMetrics` (optional, for future enhancements)
- `ce:GetCostAndUsage` (optional, for future enhancements)
- `bedrock:ListFoundationModels` (optional, for model names)

## Project Structure

```
/
├── .venv/                      # Shared Python virtual environment
├── install-systemd.sh          # Generic: Install dashboard as systemd service
├── uninstall-systemd.sh        # Generic: Uninstall systemd service
├── requirements.txt            # Shared Python dependencies
├── .env                        # Configuration (copy from .env.default)
├── .env.default               # Configuration template
├── CLAUDE.md                  # This file
├── README.md                  # User documentation
│
└── bedrock-usage/              # Bedrock usage dashboard (specific)
    ├── app.py                  # Main Flask application
    ├── bedrock-usage-template.html         # Dashboard UI template
    ├── bedrock-usage-template-pricing.html # Pricing page template
    ├── setup-bedrock-logging.sh            # Bedrock-specific: Complete setup
    ├── setup-iam-for-bedrock.sh            # Bedrock-specific: IAM setup
    ├── enable-bedrock-logging.sh           # Bedrock-specific: Enable logging
    └── grant-passrole-permission.sh        # Bedrock-specific: Grant permissions
```

**Generic scripts** (root level, reusable for all dashboards):
- `install-systemd.sh` - Install any dashboard as systemd service
- `uninstall-systemd.sh` - Remove any dashboard service

**Dashboard-specific scripts** (in bedrock-usage folder):
- `setup-bedrock-logging.sh` - Complete Bedrock logging setup
- `setup-iam-for-bedrock.sh` - Create IAM role for Bedrock
- `enable-bedrock-logging.sh` - Enable Bedrock model invocation logging
- `grant-passrole-permission.sh` - Grant PassRole permissions to users

## Setup and Running

### Local Development

1. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

2. **Create virtual environment** (optional, install-systemd.sh does this automatically):
   ```bash
   python3 -m venv .venv
   .venv/bin/pip install -r requirements.txt
   ```

3. **Configure AWS credentials** (one of):
   - Use existing `~/.aws/credentials` file
   - Set environment variables: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`
   - Run on EC2/ECS with IAM role

4. **Configure settings** (optional):
   - Copy `.env.default` to `.env` and edit for your setup
   - Set global variables: `AWS_PROFILE`, `SUBNET_ONLY`, `FQDN`
   - Or set dashboard-specific overrides: `AWS_PROFILE_BEDROCK_USAGE`, `SUBNET_ONLY_BEDROCK_USAGE`, `FQDN_BEDROCK_USAGE`

5. **Run the application**:
   ```bash
   cd bedrock-usage
   ../.venv/bin/python app.py --port 5000

   # Or from root directory:
   .venv/bin/python bedrock-usage/app.py --port 5000
   ```

6. **Access dashboard**:
   Open `http://localhost:5000` in your browser

### Systemd Service Installation (Local/VPS)

Install as a systemd service (auto-starts on boot):

```bash
# Non-root (user service, auto-starts on login)
./install-systemd.sh bedrock-usage 5000

# Root (system service, always runs)
sudo ./install-systemd.sh bedrock-usage 5000
```

Manage the service:

```bash
# View status
systemctl --user status bedrock-usage

# View logs (real-time)
journalctl --user -u bedrock-usage -f

# Stop/restart
systemctl --user stop bedrock-usage
systemctl --user restart bedrock-usage

# Uninstall
./uninstall-systemd.sh bedrock-usage
```

For user services that run even when logged out:

```bash
loginctl enable-linger
```

### AWS Lambda Deployment (Serverless)

Deploy as an AWS Lambda function with API Gateway and custom domain via Route 53:

```bash
# Setup (requires IAM role with Lambda, API Gateway, Route 53, and IAM permissions)
AWS_PROFILE=deploy-admin ./setup-lambda.sh bedrock-usage
```

The script will prompt for:
- Global settings (AWS Profile, Subnet restriction, FQDN)
- Dashboard-specific settings (optional overrides)

**Requirements:**
- AWS Route 53 hosted zone for your domain
- IAM role with elevated privileges (Lambda, API Gateway, Route 53, IAM)

**What gets created:**
- Lambda function (Python 3.11, 512MB, 30s timeout)
- API Gateway HTTP endpoint
- Route 53 DNS record (CNAME to API Gateway)
- CloudWatch logs for Lambda

**Remove deployment:**

```bash
AWS_PROFILE=deploy-admin ./remove-lambda.sh bedrock-usage app.example.com
```

**Advantages:**
- No infrastructure to manage
- Auto-scales with traffic
- Pay only for what you use
- Built-in monitoring and logging

### AWS Bedrock Setup (First-time only)

Before running the dashboard, you need to set up AWS Bedrock logging. From the `bedrock-usage/` directory:

1. **Create IAM role and policies** (requires IAM admin permissions):
   ```bash
   AWS_PROFILE=usermanager ./setup-iam-for-bedrock.sh
   ```

2. **Grant PassRole permissions to users** (requires IAM admin permissions):
   ```bash
   AWS_PROFILE=usermanager ./grant-passrole-permission.sh
   ```

3. **Enable Bedrock logging** (requires Bedrock permissions):
   ```bash
   AWS_PROFILE=dirkcli ./enable-bedrock-logging.sh
   ```

Or run the complete setup:
```bash
AWS_PROFILE=dirkcli ./setup-bedrock-logging.sh
```

These scripts create CloudWatch log groups, IAM roles, and enable Bedrock model invocation logging.

## Features

### Data Tracking
- **Invocations**: Count of API calls per user and model
- **Token Usage**: Input and output tokens tracked separately
- **Cost Analysis**: Calculated based on model pricing (configurable in `app.py`)
- **Time Series**: Daily trends for invocations and costs

### User Mapping
- Removes `bedrock-` prefix from usernames automatically
- Aggregates usage across user aliases (configured in `USER_MAP` dictionary)
- Example: `bedrock-peterdir`, `aider`, `dirkcli` all aggregate to `peterdir`

### Visualizations
- Cost breakdown by user and model (bar charts)
- Daily cost trends (line chart)
- Token usage by user and model (stacked bar charts)
- Invocation distribution (bar and doughnut charts)
- Detailed tables with sortable data

### Model Pricing
- Pricing configured in `BEDROCK_PRICING` dictionary in `bedrock-usage/app.py`
- Supports Claude, Titan, AI21, Cohere, Llama, and other models
- Separate pricing for input and output tokens (per Million tokens)
- Automatic region prefix stripping (us., global., eu., ap.)

### Configuration with Dashboard-Specific Overrides

The application supports both global and dashboard-specific configuration:

**Global configuration** (applies to all dashboards):
```bash
AWS_PROFILE=bedrock
SUBNET_ONLY=192.168.0.0/16
FQDN=bedrock-usage.example.com
```

**Dashboard-specific overrides** (only for bedrock-usage dashboard):
```bash
AWS_PROFILE_BEDROCK_USAGE=bedrock
SUBNET_ONLY_BEDROCK_USAGE=192.168.0.0/16
FQDN_BEDROCK_USAGE=bedrock-usage.example.com
```

The priority is: Dashboard-specific > Global > Default

## Adding New Dashboards

To add a new dashboard (e.g., bedrock-costs.py):

1. Create a new directory: `mkdir bedrock-costs`
2. Create the Flask app: `bedrock-costs/bedrock-costs.py`
3. Create templates: `bedrock-costs/bedrock-costs-template.html`
4. Install the service: `./install-systemd.sh bedrock-costs 5001`

Configuration variables will automatically use `_BEDROCK_COSTS` suffix.
