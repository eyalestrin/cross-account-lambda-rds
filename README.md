# Cross-Account Lambda to RDS via Direct Invoke

## Architecture
- **Account 1 (Lambda)**: S3 static website + Frontend Lambda + API Gateway
- **Account 2 (RDS)**: PostgreSQL RDS (private) + Proxy Lambda
- **Connection**: Frontend Lambda → Cross-Account Lambda Invoke → Proxy Lambda → RDS
- **Security**: IAM-based cross-account Lambda invoke, RDS in private subnet

## Prerequisites

### Disable S3 Block Public Access (Lambda Account Only)
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3control delete-public-access-block --account-id $ACCOUNT_ID
```

### Install Terraform in AWS CloudShell (Both Accounts)
```bash
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform_1.6.6_linux_amd64.zip
mkdir -p ~/bin && mv terraform ~/bin/
echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
terraform version
```

### Install Python pip (Lambda Account Only)
```bash
sudo yum install -y python3-pip
```

### Clone Repository
```bash
git clone https://github.com/eyalestrin/cross-account-lambda-rds.git
cd cross-account-lambda-rds
```

## Get Account IDs

**Lambda Account:**
```bash
aws sts get-caller-identity --query Account --output text
# Save for rds/terraform.tfvars -> lambda_account_id
```

**RDS Account:**
```bash
aws sts get-caller-identity --query Account --output text
# Save for lambda/terraform.tfvars -> rds_account_id
```

## Deployment

### 1. Deploy RDS Account
```bash
cd rds
cp terraform.tfvars.example terraform.tfvars
# Edit: lambda_account_id = "<Lambda account ID>"
terraform init
terraform apply
```

### 2. Deploy Lambda Account
```bash
cd ../lambda
cp terraform.tfvars.example terraform.tfvars
# Edit: rds_account_id = "<RDS account ID>"
terraform init
terraform apply
```

### 3. Configure Cross-Account Permissions

**In RDS Account:**
```bash
cd rds
aws lambda add-permission \
  --function-name rds-proxy-lambda \
  --statement-id AllowLambdaAccountInvoke \
  --action lambda:InvokeFunction \
  --principal <Lambda-Account-ID>
```

**In Lambda Account:**
```bash
cd lambda
aws iam put-role-policy \
  --role-name lambda-rds-execution-role \
  --policy-name CrossAccountLambdaInvoke \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "lambda:InvokeFunction",
      "Resource": "arn:aws:lambda:us-east-1:<RDS-Account-ID>:function:rds-proxy-lambda"
    }]
  }'
```

### 4. Load Sample Data

**In RDS Account:**
```bash
cd rds

# Create table
aws lambda invoke --function-name rds-proxy-lambda --cli-binary-format raw-in-base64-out --payload '{"body":"{\"sql\":\"CREATE TABLE IF NOT EXISTS transactions (transaction_id INTEGER PRIMARY KEY, description VARCHAR(30))\"}"}' response.json

# Insert data
aws lambda invoke --function-name rds-proxy-lambda --cli-binary-format raw-in-base64-out --payload '{"body":"{\"sql\":\"INSERT INTO transactions VALUES (10234567,'\''Online purchase at Amazon'\''),(20456789,'\''Gas station payment'\''),(30678901,'\''Grocery store checkout'\''),(40891234,'\''Restaurant dinner bill'\''),(50123456,'\''Monthly subscription fee'\''),(60345678,'\''ATM cash withdrawal'\''),(70567890,'\''Electric utility payment'\''),(80789012,'\''Coffee shop purchase'\''),(90901234,'\''Movie ticket booking'\''),(11223344,'\''Pharmacy medication buy'\''),(22334455,'\''Hotel accommodation charge'\''),(33445566,'\''Airline ticket purchase'\''),(44556677,'\''Car rental service'\''),(55667788,'\''Mobile phone bill payment'\''),(66778899,'\''Internet service charge'\''),(77889900,'\''Gym membership renewal'\''),(88990011,'\''Book store purchase'\''),(99001122,'\''Pet supplies shopping'\''),(12345678,'\''Home insurance premium'\''),(23456789,'\''Streaming service fee'\'') ON CONFLICT DO NOTHING\"}"}' response.json

# Verify
aws lambda invoke --function-name rds-proxy-lambda --cli-binary-format raw-in-base64-out --payload '{"body":"{\"transaction_id\":\"10234567\"}"}' response.json
cat response.json
```

### 5. Update Website

**In Lambda Account:**
```bash
cd lambda
API_ENDPOINT=$(terraform output -raw api_endpoint)
sed "s|API_ENDPOINT_PLACEHOLDER|$API_ENDPOINT|g" query.html > query_updated.html
BUCKET_NAME=$(terraform output -raw website_url | cut -d'/' -f3 | cut -d'.' -f1)
aws s3 cp query_updated.html s3://$BUCKET_NAME/index.html --content-type text/html
echo "Website: $(terraform output -raw website_url)"
```

## Access
Open the website URL and test with transaction ID: **10234567**

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed debugging steps.

**Quick Test:**
```bash
# RDS Account - verify data
aws lambda invoke --function-name rds-proxy-lambda --payload '{"body":"{\"transaction_id\":\"10234567\"}"}' response.json
cat response.json

# Lambda Account - verify frontend
aws lambda invoke --function-name transaction-rds-reader --payload '{"body":"{\"transaction_id\":\"10234567\"}"}' response.json
cat response.json
```

## Security Features
- AWS Secrets Manager stores RDS credentials
- IAM-based cross-account Lambda invoke
- RDS in private subnet (not publicly accessible)
- Lambda execution roles with least privilege
- No hardcoded credentials

## Git Commands

**Push changes:**
```bash
git add .
git commit -m "Your commit message"
git push
```

**Check status:**
```bash
git status
```

## Files
- `lambda/` - Frontend Lambda, S3 website, API Gateway
- `rds/` - PostgreSQL RDS, Proxy Lambda, Secrets Manager
- `lambda/query.html` - Static website UI
- `lambda/lambda_rds_reader.py` - Frontend Lambda code
- `rds/lambda_proxy.py` - Proxy Lambda code
- `rds/transactions_data.sql` - Sample data
