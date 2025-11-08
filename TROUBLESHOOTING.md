# Troubleshooting Guide

## Issue: "Description: Not found" in Web UI

### Step 1: Verify Data is Loaded in RDS
**In RDS Account CloudShell:**
```bash
cd rds

# Test proxy Lambda directly
aws lambda invoke \
  --function-name rds-proxy-lambda \
  --cli-binary-format raw-in-base64-out \
  --payload '{"body":"{\"transaction_id\":\"10234567\"}"}' \
  response.json

cat response.json
# Expected: {"statusCode":200,"body":"{\"10234567\": \"Online purchase at Amazon\"}"}
```

**If you see an error or null:**
```bash
# Reload the data
aws lambda invoke \
  --function-name rds-proxy-lambda \
  --cli-binary-format raw-in-base64-out \
  --payload '{"body":"{\"sql\":\"INSERT INTO transactions (transaction_id, description) VALUES (10234567, '\''Online purchase at Amazon'\''), (20456789, '\''Gas station payment'\''), (30678901, '\''Grocery store checkout'\''), (40891234, '\''Restaurant dinner bill'\''), (50123456, '\''Monthly subscription fee'\''), (60345678, '\''ATM cash withdrawal'\''), (70567890, '\''Electric utility payment'\''), (80789012, '\''Coffee shop purchase'\''), (90901234, '\''Movie ticket booking'\''), (11223344, '\''Pharmacy medication buy'\''), (22334455, '\''Hotel accommodation charge'\''), (33445566, '\''Airline ticket purchase'\''), (44556677, '\''Car rental service'\''), (55667788, '\''Mobile phone bill payment'\''), (66778899, '\''Internet service charge'\''), (77889900, '\''Gym membership renewal'\''), (88990011, '\''Book store purchase'\''), (99001122, '\''Pet supplies shopping'\''), (12345678, '\''Home insurance premium'\''), (23456789, '\''Streaming service fee'\'') ON CONFLICT DO NOTHING\"}"}' \
  response.json

cat response.json
```

### Step 2: Verify VPC Lattice Endpoint is Configured
**In Lambda Account CloudShell:**
```bash
cd lambda

# Check if VPC_LATTICE_ENDPOINT is set
aws lambda get-function-configuration \
  --function-name transaction-rds-reader \
  --query 'Environment.Variables.VPC_LATTICE_ENDPOINT' \
  --output text
```

**If it shows "None" or empty:**
```bash
# Get the endpoint from RDS account first
# Then edit terraform.tfvars and add:
# vpc_lattice_endpoint = "rds-postgres-service-xxxxx.yyyyy.vpc-lattice-svcs.us-east-1.on.aws"

terraform apply
```

### Step 3: Test Frontend Lambda
**In Lambda Account CloudShell:**
```bash
# Test frontend Lambda
aws lambda invoke \
  --function-name transaction-rds-reader \
  --cli-binary-format raw-in-base64-out \
  --payload '{"body":"{\"transaction_id\":\"10234567\"}"}' \
  response.json

cat response.json
# Expected: {"statusCode":200,"headers":{"Access-Control-Allow-Origin":"*"},"body":"{\"10234567\": \"Online purchase at Amazon\"}"}
```

### Step 4: Verify HTML has API Endpoint
**In Lambda Account CloudShell:**
```bash
cd lambda

# Download current HTML from S3
BUCKET_NAME=$(terraform output -raw website_url | cut -d'/' -f3 | cut -d'.' -f1)
aws s3 cp s3://$BUCKET_NAME/index.html downloaded.html

# Check if it has the placeholder
grep "API_ENDPOINT_PLACEHOLDER" downloaded.html

# If it shows the placeholder, update it:
API_ENDPOINT=$(terraform output -raw api_endpoint)
sed "s|API_ENDPOINT_PLACEHOLDER|$API_ENDPOINT|g" query.html > query_updated.html
aws s3 cp query_updated.html s3://$BUCKET_NAME/index.html --content-type text/html

echo "Website URL: $(terraform output -raw website_url)"
```

### Step 5: Check Browser Console
1. Open the website URL in your browser
2. Press F12 to open Developer Tools
3. Go to Console tab
4. Enter a transaction ID and click Submit
5. Look for any error messages

### Common Issues

**Issue: Lambda timeout**
- Verify NAT Gateway is deployed: `terraform apply` in Lambda account
- Check route tables have NAT Gateway routes

**Issue: VPC Lattice connection refused**
- Verify RAM share was accepted in RDS account
- Check VPC Lattice service network association

**Issue: RDS connection failed**
- Verify RDS security group allows traffic from proxy Lambda
- Check DB credentials in environment variables

**Issue: CORS error in browser**
- Verify API Gateway has CORS enabled
- Check Lambda returns proper CORS headers
