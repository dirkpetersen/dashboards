# Dashboards

A collection of dashboards that help track usage and costs across AWS services and AI platforms. Currently includes Bedrock usage tracking, with support for adding more dashboards.

<img width="1017" height="1154" alt="image" src="https://github.com/user-attachments/assets/00f51e04-ea25-4926-a34e-829fb5bcc827" />

## Features

- **Real-time monitoring** of AWS service usage and costs
- **Multi-user tracking** with aggregation and mapping capabilities
- **Interactive dashboards** with charts and detailed analytics
- **Flexible deployment** options (local, systemd service, or AWS Lambda)

## Bedrock Usage Dashboard

As using Claude Code on a per-token basis can be expensive, it's important to track usage thoroughly. The Bedrock dashboard provides:

- **Invocation tracking**: Monitor API calls per user and model
- **Token usage**: Track input and output tokens separately
- **Cost analysis**: See costs broken down by user and model
- **Time-series trends**: Daily cost and usage patterns
- **Model pricing**: Configurable pricing for all Bedrock models
- **User mapping**: Aggregate usage across multiple user identities

## Quick Start

### Prerequisites

- Python 3.7+
- AWS account with appropriate credentials
- For Bedrock dashboard: AWS Bedrock logging enabled

### Installation

```bash
# Clone or download the repository
cd dashboards

# Create and activate Python virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### Running Locally

```bash
# Start the Bedrock dashboard on default port 5000
.venv/bin/python bedrock-usage/app.py

# Or specify a custom port
.venv/bin/python bedrock-usage/app.py --port 8080
```

Then open `http://localhost:5000` in your browser.

## Deployment Options

### Option 1: User Systemd Service (Recommended for VPS/Servers)

Install as a systemd service that runs as your user (auto-starts on login):

```bash
# Install the service
./install-systemd.sh bedrock-usage 5000

# Manage the service
systemctl --user status bedrock-usage        # Check status
journalctl --user -u bedrock-usage -f       # View live logs
systemctl --user restart bedrock-usage      # Restart service

# For service to run when logged out, enable linger
loginctl enable-linger

# Uninstall when done
./uninstall-systemd.sh bedrock-usage
```

Access the dashboard at `http://localhost:5000`

### Option 2: AWS Lambda with API Gateway (Coming Soon)

Deploy as a serverless function with automatic scaling:

```bash
# Deploy to Lambda (detailed setup documentation in progress)
AWS_PROFILE=deploy-admin ./setup-lambda.sh bedrock-usage

# Remove deployment
AWS_PROFILE=deploy-admin ./remove-lambda.sh bedrock-usage app.example.com
```

**Note**: AWS Lambda deployment automation is currently under development. Detailed setup instructions will be available soon.

## Configuration

Configuration is managed through environment variables in `.env`:

```bash
# Copy the template
cp .env.default .env

# Edit with your settings
nano .env
```

**Key variables:**
- `AWS_PROFILE`: AWS CLI profile to use for credentials
- `SUBNET_ONLY`: (Optional) Restrict access to specific network CIDR block
- `FQDN`: (Optional) Domain name for Lambda deployments

**Dashboard-specific overrides** are supported. For example:
- `AWS_PROFILE_BEDROCK_USAGE`: Override AWS profile for Bedrock dashboard only

See `.env.default` for complete examples.

## AWS Permissions

The dashboards need AWS permissions to function. For the Bedrock dashboard:

- `logs:StartQuery` and `logs:GetQueryResults` - Query CloudWatch Logs
- `logs:DescribeLogStreams` - (Optional) For troubleshooting

To set up AWS permissions and enable Bedrock logging:

```bash
cd bedrock-usage

# Create IAM role for Bedrock logging
AWS_PROFILE=your-admin-profile ./setup-iam-for-bedrock.sh

# Enable Bedrock model invocation logging
AWS_PROFILE=your-bedrock-profile ./enable-bedrock-logging.sh

# Grant PassRole permissions to users
AWS_PROFILE=your-admin-profile ./grant-passrole-permission.sh
```

Or run the complete setup:

```bash
AWS_PROFILE=your-profile ./setup-bedrock-logging.sh
```

## Detailed Documentation

- **CLAUDE.md**: Developer and contributor guide with architecture details
- **bedrock-usage/CLAUDE.md**: Comprehensive Bedrock dashboard documentation including testing procedures and advanced configuration



