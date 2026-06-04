#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
CLIENT_TABLE="${CLIENT_CREDENTIALS_TABLE:-Client_Credentials}"
PROFILE_TABLE="${EMPLOYEE_PROFILES_TABLE:-Employee_Profiles}"
BUCKET_NAME="${PHOTO_BUCKET:-peoplesuite-employee-photos-${USER:-local}}"

echo "Using region: ${AWS_REGION}"
echo "Client credentials table: ${CLIENT_TABLE}"
echo "Employee profiles table: ${PROFILE_TABLE}"
echo "Photo bucket: ${BUCKET_NAME}"

if ! aws dynamodb describe-table --table-name "${CLIENT_TABLE}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws dynamodb create-table \
    --table-name "${CLIENT_TABLE}" \
    --attribute-definitions \
      AttributeName=client_id,AttributeType=S \
      AttributeName=access_token,AttributeType=S \
    --key-schema \
      AttributeName=client_id,KeyType=HASH \
      AttributeName=access_token,KeyType=RANGE \
    --global-secondary-indexes \
      "IndexName=AccessTokenIndex,KeySchema=[{AttributeName=access_token,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5}" \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --region "${AWS_REGION}"
  aws dynamodb wait table-exists --table-name "${CLIENT_TABLE}" --region "${AWS_REGION}"
else
  echo "Table ${CLIENT_TABLE} already exists"
fi

if ! aws dynamodb describe-table --table-name "${PROFILE_TABLE}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws dynamodb create-table \
    --table-name "${PROFILE_TABLE}" \
    --attribute-definitions AttributeName=employee_id,AttributeType=S \
    --key-schema AttributeName=employee_id,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --region "${AWS_REGION}"
  aws dynamodb wait table-exists --table-name "${PROFILE_TABLE}" --region "${AWS_REGION}"
else
  echo "Table ${PROFILE_TABLE} already exists"
fi

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "Bucket ${BUCKET_NAME} already exists"
else
  echo "Creating S3 bucket ${BUCKET_NAME} in ${AWS_REGION}..."
  if [ "${AWS_REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${AWS_REGION}" \
      --create-bucket-configuration LocationConstraint="${AWS_REGION}"
  fi
  echo "Created bucket ${BUCKET_NAME}"
fi

if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "ERROR: S3 bucket ${BUCKET_NAME} was not created. Check IAM permissions (s3:CreateBucket)." >&2
  exit 1
fi

SECRET_PLAIN="${CLIENT_SECRET_PLAIN:-abcdefghgobbledegook1234}"
SECRET_HASH="$(node -e "const c=require('crypto'); console.log(c.createHash('sha256').update(process.argv[1]).digest('hex'))" "${SECRET_PLAIN}")"

aws dynamodb put-item \
  --table-name "${CLIENT_TABLE}" \
  --item "{
    \"client_id\": {\"S\": \"testclient\"},
    \"access_token\": {\"S\": \"NONE\"},
    \"client_secret\": {\"S\": \"${SECRET_HASH}\"},
    \"contact_email\": {\"S\": \"test@peoplesuiteclient.com\"}
  }" \
  --region "${AWS_REGION}"

echo ""
echo "Seeded client credentials:"
echo "  client_id: testclient"
echo "  client_secret (plain): ${SECRET_PLAIN}"
echo ""
echo "Verify in AWS console: S3 → bucket '${BUCKET_NAME}', DynamoDB → ${CLIENT_TABLE}, ${PROFILE_TABLE}"
echo ""
echo "Export for services:"
echo "  export AWS_REGION=${AWS_REGION}"
echo "  export CLIENT_CREDENTIALS_TABLE=${CLIENT_TABLE}"
echo "  export EMPLOYEE_PROFILES_TABLE=${PROFILE_TABLE}"
echo "  export PHOTO_BUCKET=${BUCKET_NAME}"
