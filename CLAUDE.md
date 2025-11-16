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
.venv/bin/python bedrock-usage/app.py --port 5000

# Run on different port
.venv/bin/python bedrock-usage/app.py --port 8080
```

### Testing

Each dashboard has specific test procedures. See `bedrock-usage/CLAUDE.md` for testing the Bedrock dashboard.

```bash
# Example: Manual testing with curl
curl -s http://localhost:5000/api/usage | python3 -m json.tool | head -20
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
