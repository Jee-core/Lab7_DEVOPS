#!/bin/bash
set -e

BUCKET="cv-23l-3055"
WEB_ROOT="/var/www/html"
LOG_FILE="/var/log/cv-sync.log"

# Get instance ID via IMDSv2
TOKEN=$(curl -s -S -f -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)
if [ -n "$TOKEN" ]; then
    INSTANCE_ID=$(curl -s -S -f -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id || echo "unknown")
else
    INSTANCE_ID="unknown"
fi

# Ensure web root directory exists
mkdir -p "$WEB_ROOT"

# Sync website files from S3 bucket
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if aws s3 sync "s3://${BUCKET}/site/" "$WEB_ROOT/" --delete; then
    # Replace placeholder with EC2 and the instance ID
    if [ -f "${WEB_ROOT}/index.html" ]; then
        sed -i "s/{{HOSTED_ON}}/EC2 ${INSTANCE_ID}/g" "${WEB_ROOT}/index.html"
    fi
    chmod -R 755 "$WEB_ROOT"
    echo "[$TIMESTAMP] sync successful (instance: ${INSTANCE_ID})" >> "$LOG_FILE"
else
    EXIT_CODE=$?
    echo "[$TIMESTAMP] sync failed with status ${EXIT_CODE}" >> "$LOG_FILE"
fi
