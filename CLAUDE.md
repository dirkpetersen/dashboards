# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **monorepo** for hosting multiple AWS dashboard applications. Each dashboard monitors specific AWS services and displays usage/cost analytics through a web interface. Currently contains:
- **bedrock-usage**: AWS Bedrock invocation tracking, token usage, and cost analysis

The project is designed to support adding new dashboards (e.g., bedrock-costs, s3-usage, lambda-costs) without duplicating shared infrastructure.

## Repository Structure

```
/
├── .venv/                          # Shared Python virtual environment
├── requirements.txt                # Shared Python dependencies
├── .env                           # Configuration (copy from .env.default)
├── .env.default                   # Configuration template (global + per-dashboard)
├── CLAUDE.md                       # This file (repository guidance)
├── README.md                       # User documentation
│
├── install-systemd.sh             # Shared: Install any dashboard as systemd service
├── uninstall-systemd.sh           # Shared: Uninstall any dashboard service
├── setup-lambda.sh                # Shared: Deploy any dashboard to AWS Lambda
├── remove-lambda.sh               # Shared: Remove Lambda deployment
│
└── bedrock-usage/                 # Dashboard: Bedrock usage tracking
    ├── CLAUDE.md                  # Dashboard-specific guidance (see this for app details)
    ├── app.py                     # Flask application
    ├── bedrock-usage-template.html
    ├── bedrock-usage-template-pricing.html
    ├── bedrock-usage-more-stats.html
    └── *.sh                       # Dashboard-specific setup scripts
```

## Common Development Tasks

### Setup

```bash
# Create Python virtual environment
python3 -m venv .venv

# Activate environment
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### Running a Dashboard

```bash
# Run bedrock-usage dashboard (default port 5000)
.venv/bin/python bedrock-usage/app.py

# Run on custom port (also read from PORT environment variable)
.venv/bin/python bedrock-usage/app.py --port 8080

# Run with PORT environment variable
PORT=8080 .venv/bin/python bedrock-usage/app.py
```

### Testing

Each dashboard has specific test procedures. See `bedrock-usage/CLAUDE.md` for comprehensive testing procedures including manual testing and validation.

```bash
# Example: Manual testing with curl
curl -s http://localhost:5000/api/usage | python3 -m json.tool | head -20

# Test specific date ranges
curl -s "http://localhost:5000/api/usage?days=7" | python3 -m json.tool
curl -s "http://localhost:5000/api/usage?days=30" | python3 -m json.tool

# Time the API response
time curl -s http://localhost:5000/api/usage > /dev/null
```

### Deployment

#### Install as Systemd Service

```bash
# User service (auto-starts on login)
./install-systemd.sh bedrock-usage 5000

# System service (always runs, requires sudo)
sudo ./install-systemd.sh bedrock-usage 5000

# Manage service
systemctl --user status bedrock-usage
journalctl --user -u bedrock-usage -f
systemctl --user restart bedrock-usage

# Uninstall
./uninstall-systemd.sh bedrock-usage
```

#### Deploy to AWS Lambda

```bash
# Deploy with interactive prompts
AWS_PROFILE=deploy-admin ./setup-lambda.sh bedrock-usage

# Remove deployment
AWS_PROFILE=deploy-admin ./remove-lambda.sh bedrock-usage app.example.com
```

#### Lambda Deployment Settings Preservation

The Lambda deployment script automatically preserves configuration settings between redeployments using local metadata files. This ensures that access control and domain settings persist across code updates.

**How it works:**
1. After each deployment, settings are saved to `~/.lambda-deployments/{function-name}.metadata`
2. On the next redeployment, if a flag is not provided on the command line, the previous value is used
3. Settings are preserved per function name across different AWS profiles/accounts

**Example workflow:**
```bash
# First deployment with settings
./setup-lambda.sh bedrock-usage --profile prod --subnets-only 10.0.0.0/8 --fqdn bedrock.example.com

# Later deployment: Update code without repeating settings
./setup-lambda.sh bedrock-usage --profile prod
# Output shows: ✓ Subnets: 10.0.0.0/8
# Output shows: ✓ FQDN: bedrock.example.com
```

**Implementation details:**
- Flags `FQDN_PROVIDED` and `SUBNETS_ONLY_PROVIDED` track explicit command-line arguments
- Metadata is loaded early in the script before configuration output
- Configuration precedence: explicit args > previous settings > empty/default
- Metadata file format: Simple bash variables (`SUBNETS_ONLY="..."`, `FQDN="..."`)
- This approach works with comma-separated values (unlike Lambda environment variables which truncate at commas)

## Configuration

Configuration uses environment variables with a **hierarchy**:
1. Dashboard-specific: `{VAR}_{DASHBOARD_NAME}` (e.g., `AWS_PROFILE_BEDROCK_USAGE`)
2. Global: `{VAR}` (e.g., `AWS_PROFILE`)
3. Default: hardcoded fallback

**Supported variables:**
- `AWS_PROFILE`: AWS credentials profile to use
- `SUBNETS_ONLY`: Restrict dashboard access to specific CIDRs (comma-separated, e.g., `192.168.0.0/16,10.0.0.0/8`)
  - Note: `127.0.0.1/8` (localhost) is always implicitly allowed
- `FQDN`: Fully qualified domain name for Lambda deployments

**Example .env**:
```bash
# Global defaults
AWS_PROFILE=bedrock
SUBNETS_ONLY=192.168.0.0/16,10.0.0.0/8

# Override for bedrock-usage dashboard only
AWS_PROFILE_BEDROCK_USAGE=bedrock-prod
```

## Dashboard Architecture

Each dashboard application:
1. Is a standalone Flask app in its own directory
2. Implements `get_config()` for environment variable hierarchy
3. Implements `check_subnet_access()` middleware for access control
4. Follows naming convention: `{dashboard-name}/app.py` with HTML templates
5. Can be deployed as systemd service or Lambda function

**Key files in a dashboard directory:**
- `app.py`: Main Flask application (900-1000 lines typical)
- `{name}-template.html`: Primary dashboard UI
- `{name}-template-*.html`: Additional views (pricing, matrix, stats)
- `setup-*.sh`: Dashboard-specific AWS setup scripts

## Adding a New Dashboard

To create a new dashboard (e.g., `bedrock-costs`):

1. Create directory and files:
   ```bash
   mkdir bedrock-costs
   cp bedrock-usage/app.py bedrock-costs/app.py  # Use as template
   # Edit app.py to implement specific dashboard logic
   ```

2. Create HTML templates:
   ```bash
   cp bedrock-usage/bedrock-usage-template.html bedrock-costs/bedrock-costs-template.html
   # Edit template for your dashboard
   ```

3. Implement Flask routes and data fetching in `app.py`

4. Update `requirements.txt` if new dependencies needed

5. Install and test:
   ```bash
   .venv/bin/python bedrock-costs/app.py --port 5001
   ```

6. Deploy:
   ```bash
   ./install-systemd.sh bedrock-costs 5001
   ```

Configuration variables will automatically use `_BEDROCK_COSTS` suffix (derived from `bedrock-costs.py` filename).

## Dashboard-Specific Documentation

Refer to dashboard CLAUDE.md files for implementation details:

- **bedrock-usage**: See `bedrock-usage/CLAUDE.md` for:
  - CloudWatch Logs Insights query optimization
  - User aggregation and mapping logic
  - Bedrock pricing configuration
  - AWS permissions required
  - Complete setup procedures

## Key AWS APIs

Dashboards typically use:
- **CloudWatch Logs Insights**: Query and aggregate logs at scale
- **CloudWatch Metrics**: Fetch metric statistics
- **Cost Explorer**: Cost and usage data
- **Bedrock API**: Model invocation data (bedrock-usage)
- **IAM**: User/role information

Each dashboard's `app.py` documents specific API calls and required permissions.

## Environment Variables

### Global (applied to all dashboards)
- `AWS_PROFILE`: AWS CLI profile name
- `SUBNETS_ONLY`: Comma-separated CIDR blocks for access control (localhost always allowed)
- `FQDN`: Domain name for Lambda deployments

### Dashboard-Specific Override Pattern
Append `_{DASHBOARD_NAME}` (derived from filename without extension, uppercase, hyphens→underscores):
- `bedrock-usage.py` → `AWS_PROFILE_BEDROCK_USAGE`
- `bedrock-costs.py` → `AWS_PROFILE_BEDROCK_COSTS`
- `s3-usage.py` → `AWS_PROFILE_S3_USAGE`

See `.env.default` for examples.

## Dependencies

**Python packages** (see `requirements.txt`):
- `flask`: Web framework
- `boto3`: AWS SDK
- `python-dateutil`: Date/time utilities
- `python-dotenv`: Environment variable loading

**JavaScript libraries** (included in HTML templates):
- `Chart.js`: Data visualization
- `moment.js`: Date/time formatting

**System requirements**:
- Python 3.7+
- AWS credentials (via IAM role, ~/.aws/credentials, or environment variables)

## Troubleshooting Common Issues

### CloudWatch Logs Insights Query Timeouts
If queries are timing out:
1. Verify the `/aws/bedrock/modelinvocations` log group exists and contains recent data
2. Check CloudWatch Logs directly: `aws logs describe-log-groups --profile bedrock`
3. For large date ranges (30+ days), queries may take longer; consider breaking into smaller chunks
4. Ensure IAM user has `logs:StartQuery` and `logs:GetQueryResults` permissions

### Lambda Deployment Issues
- **Certificate validation hanging**: Check Route 53 hosted zone exists and is in the same AWS account
- **Settings not persisting**: Metadata file at `~/.lambda-deployments/{function-name}.metadata` may have stale data
- **Access denied errors**: Verify IAM profile has permissions for Lambda, API Gateway, Route 53, and ACM

### Port Already in Use
```bash
# Kill existing process
pkill -f "python app.py"

# Or use a different port
.venv/bin/python bedrock-usage/app.py --port 8081
```

### Missing AWS Credentials
Dashboards read credentials in this order:
1. `AWS_PROFILE` environment variable or .env file
2. `~/.aws/credentials` file
3. IAM role (on EC2/Lambda/ECS)
4. Environment variables: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`

## Development Notes

### Debugging Dashboard Applications

**Enable Flask debug output**:
```bash
FLASK_ENV=development .venv/bin/python bedrock-usage/app.py --port 5000
```

**Check CloudWatch Logs directly**:
```bash
# List log groups
aws logs describe-log-groups --profile bedrock

# Query log group
aws logs start-query --log-group-name /aws/bedrock/modelinvocations \
  --start-time $(date -d '7 days ago' +%s) --end-time $(date +%s) \
  --query-string 'fields @timestamp, userIdentity.principalId, @message' \
  --profile bedrock
```

### Performance Considerations

1. **CloudWatch Logs Insights**: Prefer over filter_log_events for aggregated queries (10-100x faster)
2. **Caching**: Dashboard apps implement query result caching with configurable TTL
3. **Time ranges**: Querying large date ranges (30+ days) may timeout; consider pre-aggregation or sampling
4. **Regional endpoints**: Use region-specific CloudWatch endpoints for better performance

### Adding Dashboard-Specific AWS Permissions

Dashboards may need AWS service permissions. Store setup scripts in the dashboard directory:
- `setup-iam-for-{name}.sh`: Create IAM roles/policies
- `setup-{name}-logging.sh`: Enable service logging
- `enable-{name}-logging.sh`: Configure log groups

See `bedrock-usage/` for examples.

### Flask Application Architecture

Each dashboard Flask app (e.g., `bedrock-usage/app.py`) follows a consistent pattern:

**Core components**:
1. **Configuration loading**: `get_config()` function supports dashboard-specific environment variable overrides
2. **Access control middleware**: `check_subnet_access()` validates CIDR restrictions from `SUBNETS_ONLY` variable
3. **Data fetching**: Implements AWS service queries (CloudWatch Logs, Cost Explorer, etc.)
4. **Route handlers**:
   - Index route renders HTML dashboard
   - API route returns JSON data for frontend
   - Additional routes for specific features (pricing, matrix, etc.)
5. **Caching**: Query results cached in memory with TTL to reduce AWS API calls

**Common patterns**:
- All apps run with `app.run(debug=True, host='0.0.0.0', port=args.port)`
- HTML templates use Chart.js for visualizations
- Query caching uses in-memory dict with timestamp-based TTL
- Error handling returns JSON errors with descriptive messages

**Modifying a dashboard**:
- Changes to data fetching logic go in the data function (e.g., `get_bedrock_usage()`)
- UI changes go in HTML templates
- New routes follow existing pattern: render template or return JSON
- Always validate input parameters (especially date ranges)

### Query Performance Optimization

CloudWatch Logs Insights provides 10-100x performance improvement over filter_log_events:

```bash
# Fast: Logs Insights server-side aggregation (seconds)
aws logs start-query --log-group-name /aws/bedrock/modelinvocations \
  --query-string 'stats count() by userIdentity.principalId, modelId' \
  --start-time $(date -d '7 days ago' +%s) --end-time $(date +%s) --profile bedrock

# Slow: Python-side aggregation (minutes for large datasets)
# aws logs filter_log_events + for loops in Python
```

**Best practices**:
1. Always use Logs Insights for aggregation queries
2. Let CloudWatch handle grouping/counting when possible
3. Cache results with reasonable TTL (10 minutes typical)
4. Test queries directly in AWS CloudWatch console before implementing
