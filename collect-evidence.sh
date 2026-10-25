#!/bin/bash
export MSYS_NO_PATHCONV=1

# Check arguments: exactly three required
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <bucket-name> <ec2-address> <lambda-address>"
    exit 1
fi

BUCKET="$1"
EC2_ADDR="$2"
LAMBDA_ADDR="$3"
OUTPUT_FILE="evidence.txt"

# Clean previous output
rm -f "$OUTPUT_FILE"

# Helper function to run commands and record output
record_section() {
    local section_name="$1"
    shift
    echo "== $section_name ==" >> "$OUTPUT_FILE"
    if ! "$@" >> "$OUTPUT_FILE" 2>&1; then
        echo "Command failed for section: $section_name" >> "$OUTPUT_FILE"
    fi
    echo "" >> "$OUTPUT_FILE"
}

# 1. caller
record_section "caller" aws sts get-caller-identity

# 2. public-access
record_section "public-access" aws s3api get-public-access-block --bucket "$BUCKET"

# 3. versioning
record_section "versioning" aws s3api get-bucket-versioning --bucket "$BUCKET"

# 4. objects
record_section "objects" aws s3 ls "s3://${BUCKET}/site/" --recursive

# 5. ec2-policy
record_section "ec2-policy" aws iam get-role-policy --role-name cv-ec2-role-23l-3055 --policy-name cv-ec2-permissions

# 6. lambda-policy
echo "== lambda-policy ==" >> "$OUTPUT_FILE"
aws iam list-attached-role-policies --role-name cv-lambda-role-23l-3055 >> "$OUTPUT_FILE" 2>&1 || echo "list-attached-role-policies failed" >> "$OUTPUT_FILE"
aws iam get-role-policy --role-name cv-lambda-role-23l-3055 --policy-name cv-lambda-permissions >> "$OUTPUT_FILE" 2>&1 || echo "get-role-policy failed" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# 7. security-group
record_section "security-group" aws ec2 describe-security-groups --filters "Name=group-name,Values=cv-sg-23l-3055" --query "SecurityGroups[*].IpPermissions"

# 8. instance
record_section "instance" aws ec2 describe-instances --filters "Name=tag:Name,Values=cv-ec2-23l-3055" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].{InstanceType:InstanceType,InstanceId:InstanceId,IamInstanceProfile:IamInstanceProfile.Arn,MetadataOptions:MetadataOptions}"

# 9. endpoints
echo "== endpoints ==" >> "$OUTPUT_FILE"
EC2_URL="http://${EC2_ADDR}/"
if [[ "$EC2_ADDR" =~ ^https?:// ]]; then
    EC2_URL="${EC2_ADDR}/"
fi
curl -s -S -o /dev/null -w "EC2: status=%{http_code} content-type=%{content_type}\n" "$EC2_URL" >> "$OUTPUT_FILE" 2>&1 || echo "curl EC2 failed" >> "$OUTPUT_FILE"
curl -s -S -o /dev/null -w "Lambda: status=%{http_code} content-type=%{content_type}\n" "$LAMBDA_ADDR" >> "$OUTPUT_FILE" 2>&1 || echo "curl Lambda failed" >> "$OUTPUT_FILE"
curl -s -S -o /dev/null -w "Direct S3: status=%{http_code} content-type=%{content_type}\n" "https://${BUCKET}.s3.ap-southeast-2.amazonaws.com/site/index.html" >> "$OUTPUT_FILE" 2>&1 || echo "curl S3 failed" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# 10. lambda-logs
echo "== lambda-logs ==" >> "$OUTPUT_FILE"
if aws logs tail "/aws/lambda/cv-func-23l-3055" --since 1h >> "$OUTPUT_FILE" 2>&1; then
    :
else
    aws logs filter-log-events --log-group-name "/aws/lambda/cv-func-23l-3055" --query "events[*].message" --output text >> "$OUTPUT_FILE" 2>&1 || echo "Failed to fetch lambda logs" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

# 11. log-retention
record_section "log-retention" aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/cv-func-23l-3055" --query "logGroups[*].{logGroupName:logGroupName,retentionInDays:retentionInDays}"

echo "DONE"
