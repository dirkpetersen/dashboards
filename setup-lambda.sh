#!/bin/bash

# Deploy Flask application as AWS Lambda function with API Gateway
# Supports all dashboards with their own settings
# Usage: AWS_PROFILE=deploy-admin ./setup-lambda.sh bedrock-usage [--no-dns]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
NO_DNS=false
DASHBOARD_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-dns)
            NO_DNS=true
            shift
            ;;
        *)
            if [ -z "$DASHBOARD_NAME" ]; then
                DASHBOARD_NAME="$1"
            else
                echo "Error: Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if dashboard name was provided
if [ -z "$DASHBOARD_NAME" ]; then
    echo "Usage: $0 <dashboard-name> [--no-dns]"
    echo ""
    echo "Options:"
    echo "  --no-dns    Deploy without Route 53 DNS (use API Gateway endpoint only)"
    echo ""
    echo "Examples:"
    echo "  AWS_PROFILE=deploy-admin ./setup-lambda.sh bedrock-usage"
    echo "  AWS_PROFILE=deploy-admin ./setup-lambda.sh bedrock-usage --no-dns"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIR="$SCRIPT_DIR/$DASHBOARD_NAME"

# Validate dashboard directory exists
if [ ! -d "$DASHBOARD_DIR" ]; then
    echo "❌ Error: Dashboard directory '$DASHBOARD_DIR' not found"
    exit 1
fi

if [ ! -f "$DASHBOARD_DIR/app.py" ]; then
    echo "❌ Error: app.py not found in $DASHBOARD_DIR"
    exit 1
fi

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}AWS Lambda Deployment for $DASHBOARD_NAME${NC}"
if [ "$NO_DNS" = true ]; then
    echo -e "${BLUE}(No Route 53 DNS - API Gateway endpoint only)${NC}"
fi
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Check AWS credentials
echo -e "${BLUE}Checking AWS credentials...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)

if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: Unable to authenticate with AWS${NC}"
    echo "Make sure AWS_PROFILE is set correctly"
    exit 1
fi

REGION=$(aws configure get region || echo "us-east-1")
echo -e "${GREEN}✓ Account ID: $ACCOUNT_ID${NC}"
echo -e "${GREEN}✓ Region: $REGION${NC}"
echo ""

# Function to prompt for input with default value
prompt_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local input_value=""

    if [ -z "$default" ]; then
        read -p "  $prompt: " input_value
    else
        read -p "  $prompt [$default]: " input_value
        input_value="${input_value:-$default}"
    fi

    eval "$var_name='$input_value'"
}

# Function to get app-specific variable name
get_app_var() {
    local var_name="$1"
    echo "${var_name}_${DASHBOARD_NAME^^}"
}

# Prompt for configuration
echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}CONFIGURATION SETTINGS${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${BLUE}Global Settings (apply to all dashboards):${NC}"
prompt_input "AWS Profile" "default" "AWS_PROFILE"
prompt_input "Subnets restriction (comma-separated CIDRs, leave empty for no restriction)" "" "SUBNETS_ONLY"

if [ "$NO_DNS" = false ]; then
    prompt_input "FQDN (fully qualified domain name)" "" "FQDN"
fi
echo ""

APP_AWS_VAR=$(get_app_var "AWS_PROFILE")
APP_SUBNET_VAR=$(get_app_var "SUBNETS_ONLY")
APP_FQDN_VAR=$(get_app_var "FQDN")

echo -e "${BLUE}Dashboard-Specific Settings (override global):${NC}"
echo "(Leave blank to use global settings)"
prompt_input "AWS Profile (app-specific)" "" "APP_AWS_PROFILE"
prompt_input "Subnets restriction (app-specific)" "" "APP_SUBNETS_ONLY"

if [ "$NO_DNS" = false ]; then
    prompt_input "FQDN (app-specific)" "" "APP_FQDN"
fi
echo ""

# Use global or app-specific values
FINAL_AWS_PROFILE="${APP_AWS_PROFILE:-$AWS_PROFILE}"
FINAL_SUBNETS_ONLY="${APP_SUBNETS_ONLY:-$SUBNETS_ONLY}"
FINAL_FQDN="${APP_FQDN:-$FQDN}"

if [ "$NO_DNS" = false ] && [ -z "$FINAL_FQDN" ]; then
    echo -e "${RED}❌ Error: FQDN is required (use --no-dns to skip DNS setup)${NC}"
    exit 1
fi

echo -e "${GREEN}✓ AWS Profile: $FINAL_AWS_PROFILE${NC}"
echo -e "${GREEN}✓ Subnets Only: ${FINAL_SUBNETS_ONLY:-none}${NC}"
if [ "$NO_DNS" = false ]; then
    echo -e "${GREEN}✓ FQDN: $FINAL_FQDN${NC}"
fi
echo ""

# Extract domain from FQDN (last two parts for Route 53 hosted zone)
# Only if DNS is enabled
if [ "$NO_DNS" = false ]; then
    # Example: app.example.com -> example.com
    IFS='.' read -ra FQDN_PARTS <<< "$FINAL_FQDN"
    DOMAIN_LENGTH=${#FQDN_PARTS[@]}

    if [ $DOMAIN_LENGTH -lt 2 ]; then
        echo -e "${RED}❌ Error: Invalid FQDN format: $FINAL_FQDN${NC}"
        exit 1
    fi

    # Get the last two parts (domain + TLD)
    HOSTED_ZONE="${FQDN_PARTS[$((DOMAIN_LENGTH-2))]} . ${FQDN_PARTS[$((DOMAIN_LENGTH-1))]}"
    HOSTED_ZONE="${HOSTED_ZONE// /}"
fi

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}LAMBDA DEPLOYMENT${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Step 1: Check if Route 53 hosted zone exists (skip if --no-dns)
if [ "$NO_DNS" = false ]; then
    echo -e "${BLUE}Step 1: Checking Route 53 hosted zone...${NC}"
    ZONE_ID=$(aws route53 list-hosted-zones-by-name --query "HostedZones[?Name=='${HOSTED_ZONE}.'].Id" --output text 2>/dev/null | cut -d'/' -f3)

    if [ -z "$ZONE_ID" ]; then
        echo -e "${RED}❌ Error: Route 53 hosted zone not found for: $HOSTED_ZONE${NC}"
        echo "Please create a hosted zone in Route 53 first"
        exit 1
    fi

    echo -e "${GREEN}✓ Found hosted zone: $HOSTED_ZONE (ID: $ZONE_ID)${NC}"
    echo ""
fi

# Step 2: Create deployment package
echo -e "${BLUE}Step 2: Creating deployment package...${NC}"
LAMBDA_FUNCTION_NAME="${DASHBOARD_NAME}-api"
BUILD_DIR="/tmp/${LAMBDA_FUNCTION_NAME}-build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Copy application files
cp "$DASHBOARD_DIR/app.py" "$BUILD_DIR/"
cp "$DASHBOARD_DIR"/*.html "$BUILD_DIR/" 2>/dev/null || true

# Create requirements file in build dir
cp "$SCRIPT_DIR/requirements.txt" "$BUILD_DIR/"

# Create a minimal .env file for Lambda (will be loaded by app.py)
cat > "$BUILD_DIR/.env" << ENVEOF
# Lambda deployment - environment variables set by lambda_handler.py
ENVEOF

# Create config file with deployment settings
# Note: AWS_PROFILE is NOT used in Lambda - Lambda uses IAM roles instead
cat > "$BUILD_DIR/config.json" << EOF
{
  "subnets_only": "$FINAL_SUBNETS_ONLY",
  "fqdn": "$FINAL_FQDN"
}
EOF

# Create Lambda handler wrapper
cat > "$BUILD_DIR/lambda_handler.py" << 'HANDLER_EOF'
import json
import sys
import os
from pathlib import Path

# Load config
config_file = Path(__file__).parent / 'config.json'
config = json.load(open(config_file))

# Set environment variables
# Note: Lambda uses IAM role for AWS credentials, NOT AWS_PROFILE
if config.get('subnets_only'):
    os.environ['SUBNETS_ONLY'] = config['subnets_only']
if config.get('fqdn'):
    os.environ['FQDN'] = config['fqdn']

# Import app
from app import app

def lambda_handler(event, context):
    """Lambda entry point for Flask application"""

    # Handle API Gateway v2 format
    if event.get('version') == '2.0':
        method = event['requestContext']['http']['method']
        path = event['rawPath']
        body = event.get('body', '')
        headers = event.get('headers', {})
    else:
        # API Gateway v1 format
        method = event['httpMethod']
        path = event['path']
        body = event.get('body', '')
        headers = event.get('headers', {})

    # Create WSGI environ
    environ = {
        'REQUEST_METHOD': method,
        'SCRIPT_NAME': '',
        'PATH_INFO': path,
        'QUERY_STRING': event.get('rawQueryString', ''),
        'CONTENT_TYPE': headers.get('content-type', ''),
        'CONTENT_LENGTH': str(len(body)) if body else '',
        'SERVER_NAME': headers.get('host', 'lambda.amazonaws.com').split(':')[0],
        'SERVER_PORT': headers.get('x-forwarded-port', '443'),
        'SERVER_PROTOCOL': 'HTTP/1.1',
        'wsgi.version': (1, 0),
        'wsgi.url_scheme': headers.get('x-forwarded-proto', 'https'),
        'wsgi.input': None,
        'wsgi.errors': sys.stderr,
        'wsgi.multithread': True,
        'wsgi.multiprocess': False,
        'wsgi.run_once': False,
    }

    # Add headers to environ
    for header, value in headers.items():
        header_key = 'HTTP_' + header.upper().replace('-', '_')
        environ[header_key] = value

    # Call Flask app
    response_data = []
    status = None
    response_headers = None

    def start_response(status_str, headers_list):
        nonlocal status, response_headers
        status = int(status_str.split()[0])
        response_headers = dict(headers_list)

    response_data = app.wsgi_app(environ, start_response)

    # Combine response
    body_str = ''.join([chunk.decode('utf-8') if isinstance(chunk, bytes) else chunk for chunk in response_data])

    return {
        'statusCode': status or 200,
        'headers': response_headers or {},
        'body': body_str
    }
HANDLER_EOF

echo -e "${GREEN}✓ Created deployment package${NC}"
echo ""

# Step 3: Create Lambda function (or update if exists)
echo -e "${BLUE}Step 3: Creating/updating Lambda function...${NC}"

# Install dependencies
pip_output=$(.venv/bin/pip install -q -r "$BUILD_DIR/requirements.txt" -t "$BUILD_DIR/" 2>&1 || true)

# Create zip file
cd "$BUILD_DIR"
zip -r -q "${LAMBDA_FUNCTION_NAME}.zip" . -x "*.git*" "*.venv*" "*__pycache__*" "*.pyc"
cd - > /dev/null

LAMBDA_ROLE_NAME="lambda-${DASHBOARD_NAME}-role"
LAMBDA_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"

# Check if function exists
if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" 2>/dev/null; then
    echo -e "${YELLOW}Updating existing Lambda function...${NC}"
    aws lambda update-function-code \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --zip-file "fileb://${BUILD_DIR}/${LAMBDA_FUNCTION_NAME}.zip" > /dev/null
else
    echo -e "${YELLOW}Creating new Lambda function...${NC}"

    # Check if role exists, if not create it
    if ! aws iam get-role --role-name "$LAMBDA_ROLE_NAME" 2>/dev/null; then
        echo -e "${YELLOW}Creating IAM role for Lambda...${NC}"

        TRUST_POLICY='{
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Principal": {
                "Service": "lambda.amazonaws.com"
              },
              "Action": "sts:AssumeRole"
            }
          ]
        }'

        aws iam create-role \
            --role-name "$LAMBDA_ROLE_NAME" \
            --assume-role-policy-document "$TRUST_POLICY" > /dev/null

        # Attach policy for CloudWatch logs
        aws iam attach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole > /dev/null

        # Create and attach policy for Bedrock logs access
        BEDROCK_POLICY_NAME="lambda-bedrock-logs-access"
        BEDROCK_POLICY_DOCUMENT='{
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Action": [
                "logs:*"
              ],
              "Resource": "arn:aws:logs:*:*:log-group:/aws/bedrock/modelinvocations*"
            },
            {
              "Effect": "Allow",
              "Action": [
                "bedrock:GetModelInvocationLoggingConfiguration"
              ],
              "Resource": "*"
            }
          ]
        }'

        aws iam put-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-name "$BEDROCK_POLICY_NAME" \
            --policy-document "$BEDROCK_POLICY_DOCUMENT" > /dev/null

        echo -e "${GREEN}✓ Created IAM role: $LAMBDA_ROLE_NAME${NC}"

        # Wait for IAM role to propagate
        echo -e "${YELLOW}Waiting for IAM role to propagate (10 seconds)...${NC}"
        sleep 10
    fi

    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.11 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda_handler.lambda_handler \
        --timeout 30 \
        --memory-size 512 \
        --zip-file "fileb://${BUILD_DIR}/${LAMBDA_FUNCTION_NAME}.zip" > /dev/null

    # Wait for function to be created
    sleep 2
fi

echo -e "${GREEN}✓ Lambda function ready: $LAMBDA_FUNCTION_NAME${NC}"
echo ""

# Step 4: Create/update API Gateway
echo -e "${BLUE}Step 4: Setting up API Gateway...${NC}"

API_NAME="${DASHBOARD_NAME}-api"

# Check if API exists
API_ID=$(aws apigatewayv2 get-apis --query "Items[?Name=='$API_NAME'].ApiId" --output text 2>/dev/null)

if [ -z "$API_ID" ]; then
    echo -e "${YELLOW}Creating new API Gateway...${NC}"

    API_ID=$(aws apigatewayv2 create-api \
        --name "$API_NAME" \
        --protocol-type HTTP \
        --target "arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}" \
        --query 'ApiId' \
        --output text)
else
    echo -e "${YELLOW}API Gateway already exists: $API_ID${NC}"
fi

API_ENDPOINT="${API_ID}.execute-api.${REGION}.amazonaws.com"

# Grant API Gateway permission to invoke Lambda
echo -e "${YELLOW}Granting API Gateway invoke permission to Lambda...${NC}"
aws lambda add-permission \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --statement-id AllowAPIGatewayInvoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*" 2>/dev/null || echo "Permission already exists"

echo -e "${GREEN}✓ API Gateway: $API_ID${NC}"
echo -e "${GREEN}✓ API Endpoint: https://${API_ENDPOINT}${NC}"
echo ""

# Step 5: Create DNS record (skip if --no-dns)
if [ "$NO_DNS" = false ]; then
    echo -e "${BLUE}Step 5: Creating Route 53 DNS record...${NC}"

    # Check if record exists
    EXISTING_RECORD=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$ZONE_ID" \
        --query "ResourceRecordSets[?Name=='${FINAL_FQDN}.'].ResourceRecords[0].Value" \
        --output text 2>/dev/null || echo "")

    if [ "$EXISTING_RECORD" != "None" ] && [ -n "$EXISTING_RECORD" ]; then
        echo -e "${YELLOW}Updating existing DNS record...${NC}"

        CHANGE_BATCH="{
          \"Changes\": [{
            \"Action\": \"UPSERT\",
            \"ResourceRecordSet\": {
              \"Name\": \"${FINAL_FQDN}\",
              \"Type\": \"CNAME\",
              \"TTL\": 300,
              \"ResourceRecords\": [{\"Value\": \"${API_ENDPOINT}\"}]
            }
          }]
        }"
    else
        CHANGE_BATCH="{
          \"Changes\": [{
            \"Action\": \"CREATE\",
            \"ResourceRecordSet\": {
              \"Name\": \"${FINAL_FQDN}\",
              \"Type\": \"CNAME\",
              \"TTL\": 300,
              \"ResourceRecords\": [{\"Value\": \"${API_ENDPOINT}\"}]
            }
          }]
        }"
    fi

    CHANGE_INFO=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$ZONE_ID" \
        --change-batch "$CHANGE_BATCH" \
        --query 'ChangeInfo.Id' \
        --output text)

    echo -e "${GREEN}✓ DNS record created: $FINAL_FQDN -> $API_ENDPOINT${NC}"
    echo ""
fi

# Cleanup
rm -rf "$BUILD_DIR"

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Lambda Deployment Complete!${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Deployment Details:${NC}"
echo "  Application: $DASHBOARD_NAME"
echo "  Lambda Function: $LAMBDA_FUNCTION_NAME"
echo "  API Gateway: $API_ID"
if [ "$NO_DNS" = false ]; then
    echo "  API Endpoint: https://${API_ENDPOINT}"
    echo "  Custom Domain: https://${FINAL_FQDN}"
    echo "  Region: $REGION"
    echo ""
    echo -e "${YELLOW}Note: DNS propagation may take a few minutes${NC}"
else
    echo "  Public Endpoint: https://${API_ENDPOINT}"
    echo "  Region: $REGION"
    echo ""
    echo -e "${YELLOW}Your dashboard is now publicly accessible at:${NC}"
    echo -e "${BLUE}https://${API_ENDPOINT}${NC}"
fi
echo ""
