#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function for error handling
handle_error() {
    log "Error occurred in script at line: ${1}."
    log "Exiting..."
    exit 1
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Define variables
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LAMBDA_CODE_BUCKET="${AWS_ACCOUNT_ID}-lambda-code-bucket"
LAMBDA_ZIP="visitor_counter.zip"
AWS_REGION="eu-west-2"
CERTIFICATE_REGION="us-east-1"  # ACM certificates for CloudFront must be in us-east-1
DOMAIN_NAME="peter.iamatta.com"

# Check if 7z (7-Zip) is installed
if ! command -v 7z &> /dev/null; then
    log "7z command not found. Please install 7-Zip utility."
    exit 1
fi

# Zip Lambda function code
log "Zipping Lambda function..."
cd backend/lambda || handle_error $LINENO
7z a -tzip $LAMBDA_ZIP visitor_counter.py
cd ../../ || handle_error $LINENO

# Create Lambda bucket if it doesn't already exist
if ! aws s3api head-bucket --bucket $LAMBDA_CODE_BUCKET 2>/dev/null; then
    log "Creating Lambda code S3 bucket..."
    aws s3api create-bucket --bucket $LAMBDA_CODE_BUCKET --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
else
    log "Bucket $LAMBDA_CODE_BUCKET already exists."
fi

# Upload Lambda function to S3
log "Uploading Lambda function to S3..."
aws s3 cp backend/lambda/$LAMBDA_ZIP s3://$LAMBDA_CODE_BUCKET/

# Create ACM Certificate
log "Creating ACM Certificate..."
CERTIFICATE_ARN=$(aws acm request-certificate --domain-name $DOMAIN_NAME --validation-method DNS --region $CERTIFICATE_REGION --query CertificateArn --output text)

log "Waiting for certificate validation..."
aws acm wait certificate-validated --certificate-arn $CERTIFICATE_ARN --region $CERTIFICATE_REGION

# Deploy CloudFormation stacks
log "Deploying CloudFormation stacks..."

# Deploy backend resources (Lambda, API Gateway, DynamoDB)
log "Deploying backend stack..."
aws cloudformation deploy \
  --template-file backend/cloudformation/backend.yml \
  --stack-name cloud-resume-backend \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides LambdaCodeBucket=$LAMBDA_CODE_BUCKET

# Deploy frontend resources (S3, CloudFront)
log "Deploying frontend stack..."
aws cloudformation deploy \
  --template-file backend/cloudformation/frontend.yml \
  --stack-name cloud-resume-frontend \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides DomainName=$DOMAIN_NAME CertificateArn=$CERTIFICATE_ARN

log "Deployment complete!"

# Get API Gateway URL
API_URL=$(aws cloudformation describe-stacks --stack-name cloud-resume-backend --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text)

log "API Gateway URL: $API_URL"
log "Testing API endpoint..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" $API_URL)

if [ $RESPONSE -eq 200 ]; then
    log "API test successful!"
else
    log "API test failed with status code: $RESPONSE"
    log "Check Lambda function logs for more details."
fi