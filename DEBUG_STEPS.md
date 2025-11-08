# Debug Steps - Run These in Order

## RDS Account - Test Proxy Lambda

```bash
cd rds

# Test 1: Check if proxy Lambda can query
aws lambda invoke --function-name rds-proxy-lambda --cli-binary-format raw-in-base64-out --payload '{"body":"{\"transaction_id\":\"10234567\"}"}' test.json
cat test.json
```

**Expected output:** `{"statusCode":200,"body":"{\"10234567\": \"Online purchase at Amazon\"}"}`

**If you see `{"statusCode":200,"body":"{\"10234567\": null}"}` then data is NOT loaded. Run:**

```bash
# Create table
aws lambda invoke --function-name rds-proxy-lambda --cli-binary-format raw-in-base64-out --payload '{"body":"{\"sql\":\"DROP TABLE IF EXISTS transactions; CREATE TABLE transactions (transaction_id INTEGER PRIMARY KEY, description VARCHAR(30))\"}"}' test.json
cat test.json

# Insert data
aws lambda invoke --function-name rds-proxy-lambda --cli-binary-format raw-in-base64-out --payload '{"body":"{\"sql\":\"INSERT INTO transactions VALUES (10234567,'\''Online purchase at Amazon'\''),(20456789,'\''Gas station payment'\''),(30678901,'\''Grocery store checkout'\''),(40891234,'\''Restaurant dinner bill'\''),(50123456,'\''Monthly subscription fee'\''),(60345678,'\''ATM cash withdrawal'\''),(70567890,'\''Electric utility payment'\''),(80789012,'\''Coffee shop purchase'\''),(90901234,'\''Movie ticket booking'\''),(11223344,'\''Pharmacy medication buy'\''),(22334455,'\''Hotel accommodation charge'\''),(33445566,'\''Airline ticket purchase'\''),(44556677,'\''Car rental service'\''),(55667788,'\''Mobile phone bill payment'\''),(66778899,'\''Internet service charge'\''),(77889900,'\''Gym membership renewal'\''),(88990011,'\''Book store purchase'\''),(99001122,'\''Pet supplies shopping'\''),(12345678,'\''Home insurance premium'\''),(23456789,'\''Streaming service fee'\'')\"}"}' test.json
cat test.json

# Verify
aws lambda invoke --function-name rds-proxy-lambda --cli-binary-format raw-in-base64-out --payload '{"body":"{\"transaction_id\":\"10234567\"}"}' test.json
cat test.json
```

## Lambda Account - Test Frontend Lambda

```bash
cd lambda

# Test 2: Check if VPC Lattice endpoint is set
aws lambda get-function-configuration --function-name transaction-rds-reader --query 'Environment.Variables.VPC_LATTICE_ENDPOINT' --output text
```

**Expected:** `rds-postgres-service-xxxxx.yyyyy.vpc-lattice-svcs.us-east-1.on.aws`

**If empty, set it in terraform.tfvars and run `terraform apply`**

```bash
# Test 3: Test frontend Lambda
aws lambda invoke --function-name transaction-rds-reader --cli-binary-format raw-in-base64-out --payload '{"body":"{\"transaction_id\":\"10234567\"}"}' test.json
cat test.json
```

**Expected:** `{"statusCode":200,"headers":{"Access-Control-Allow-Origin":"*"},"body":"{\"10234567\": \"Online purchase at Amazon\"}"}`

## Lambda Account - Update HTML

```bash
cd lambda

# Test 4: Check current HTML in S3
BUCKET_NAME=$(terraform output -raw website_url | cut -d'/' -f3 | cut -d'.' -f1)
aws s3 cp s3://$BUCKET_NAME/index.html current.html
grep "API_ENDPOINT" current.html
```

**If you see `API_ENDPOINT_PLACEHOLDER`, update it:**

```bash
API_ENDPOINT=$(terraform output -raw api_endpoint)
echo "API Endpoint: $API_ENDPOINT"
sed "s|API_ENDPOINT_PLACEHOLDER|$API_ENDPOINT|g" query.html > query_updated.html
aws s3 cp query_updated.html s3://$BUCKET_NAME/index.html --content-type text/html

# Verify
aws s3 cp s3://$BUCKET_NAME/index.html - | grep "const API_ENDPOINT"
```

## Test Website

```bash
terraform output -raw website_url
```

Open URL in browser, enter: **10234567**

Expected: **Description: Online purchase at Amazon**
