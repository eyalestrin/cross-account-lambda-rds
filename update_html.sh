#!/bin/bash
# Run this in Lambda Account CloudShell

cd lambda

echo "=== STEP 1: Get API endpoint ==="
API_ENDPOINT=$(terraform output -raw api_endpoint)
echo "API Endpoint: $API_ENDPOINT"

echo "=== STEP 2: Update HTML ==="
sed "s|API_ENDPOINT_PLACEHOLDER|$API_ENDPOINT|g" query.html > query_updated.html

echo "=== STEP 3: Verify HTML has endpoint ==="
grep "const API_ENDPOINT" query_updated.html

echo "=== STEP 4: Upload to S3 ==="
BUCKET_NAME=$(terraform output -raw website_url | cut -d'/' -f3 | cut -d'.' -f1)
aws s3 cp query_updated.html s3://$BUCKET_NAME/index.html --content-type text/html

echo "=== STEP 5: Verify S3 has correct HTML ==="
aws s3 cp s3://$BUCKET_NAME/index.html - | grep "const API_ENDPOINT"

echo "=== Website URL ==="
terraform output -raw website_url
