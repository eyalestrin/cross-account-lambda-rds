# Troubleshooting Guide

## Issue: "Description: Not found"

### Step 1: Verify RDS Data
**In RDS Account:**
```bash
cd rds
aws lambda invoke --function-name rds-proxy-lambda --cli-binary-format raw-in-base64-out --payload '{"body":"{\"transaction_id\":\"10234567\"}"}' test.json
cat test.json
```

**Expected:** `{"statusCode":200,"body":"{\"10234567\": \"Online purchase at Amazon\"}"}`

**If null, reload data:**
```bash
aws lambda invoke --function-name rds-proxy-lambda --cli-binary-format raw-in-base64-out --payload '{"body":"{\"sql\":\"INSERT INTO transactions VALUES (10234567,'\''Online purchase at Amazon'\'') ON CONFLICT DO NOTHING\"}"}' test.json
```

### Step 2: Verify Frontend Lambda
**In Lambda Account:**
```bash
cd lambda
aws lambda invoke --function-name transaction-rds-reader --cli-binary-format raw-in-base64-out --payload '{"body":"{\"transaction_id\":\"10234567\"}"}' test.json
cat test.json
```

**Expected:** `{"statusCode":200,"headers":{"Access-Control-Allow-Origin":"*"},"body":"{\"10234567\": \"Online purchase at Amazon\"}"}`

**If AccessDeniedException:**
- Check cross-account Lambda permission in RDS account
- Check IAM policy in Lambda account role

### Step 3: Verify HTML
**In Lambda Account:**
```bash
cd lambda
BUCKET_NAME=$(terraform output -raw website_url | cut -d'/' -f3 | cut -d'.' -f1)
aws s3 cp s3://$BUCKET_NAME/index.html - | grep "const API_ENDPOINT"
```

**If shows placeholder, update:**
```bash
API_ENDPOINT=$(terraform output -raw api_endpoint)
sed "s|API_ENDPOINT_PLACEHOLDER|$API_ENDPOINT|g" query.html > query_updated.html
aws s3 cp query_updated.html s3://$BUCKET_NAME/index.html --content-type text/html
```

## Common Issues

**AccessDeniedException:**
- Add Lambda permission in RDS account
- Add IAM policy to Lambda role in Lambda account

**RDS Connection Failed:**
- Check RDS security group allows traffic from proxy Lambda
- Verify DB credentials in environment variables

**CORS Error:**
- Verify API Gateway has CORS enabled
- Check Lambda returns proper CORS headers
