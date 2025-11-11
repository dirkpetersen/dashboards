#!/bin/bash

# Grant iam:PassRole permission to users who need to enable Bedrock logging
# Usage: AWS_PROFILE=usermanager ./grant-passrole-permission.sh

set -e

echo "=========================================="
echo "Grant PassRole Permission for Bedrock"
echo "=========================================="
echo ""

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/BedrockCloudWatchLoggingRole"

echo "✓ AWS Account ID: $ACCOUNT_ID"
echo ""

# Create inline policy for IAM users to allow PassRole
USERS=("aider" "dirkcli")

for USER in "${USERS[@]}"; do
    echo "Granting iam:PassRole permission to user: $USER"

    POLICY_DOCUMENT='{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "iam:PassRole",
          "Resource": "'"$ROLE_ARN"'"
        }
      ]
    }'

    if aws iam put-user-policy \
        --user-name "$USER" \
        --policy-name "BedrockPassRolePolicy" \
        --policy-document "$POLICY_DOCUMENT" 2>/dev/null; then
        echo "✓ Granted PassRole permission to $USER"
    else
        echo "⚠ Warning: Could not grant permission to $USER (user may not exist)"
    fi
    echo ""
done

echo "=========================================="
echo "Permissions Updated!"
echo "=========================================="
echo ""
echo "Now you can enable Bedrock logging with:"
echo "  AWS_PROFILE=bedrock ./enable-bedrock-logging.sh"
echo ""
