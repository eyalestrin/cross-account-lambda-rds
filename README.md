# Cross-Account Lambda to RDS via VPC Lattice

## Architecture
- **Account 1 (Lambda)**: S3 static website + Frontend Lambda function + VPC Lattice Service Network
- **Account 2 (RDS)**: PostgreSQL RDS (private) + Proxy Lambda + VPC Lattice Service + AWS Secrets Manager
- **Connection**: Frontend Lambda → VPC Lattice (HTTPS) → Proxy Lambda → RDS
- **Security**: VPC Lattice with AWS_IAM authentication, RDS in private subnet

**VPC Lattice Flow:**
1. Frontend Lambda (in VPC) calls VPC Lattice HTTPS endpoint
2. DNS resolution via NAT Gateway to internet
3. VPC Lattice routes traffic via AWS backbone
4. VPC Lattice routes to Proxy Lambda in Account 2
5. Proxy Lambda (in VPC) connects to private RDS
6. Returns data through VPC Lattice to Frontend Lambda

**Cost**: ~$32/month for NAT Gateway + $0.045/GB data transfer

## Prerequisites

**Note**: This solution uses VPC Lattice for cross-account communication with NAT Gateway. Cost: ~$32/month for NAT Gateway + data transfer.

### Disable S3 Block Public Access (Lambda Account Only)
Run in Lambda account CloudShell:

```bash
# Get your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Disable account-level S3 Block Public Access
aws s3control delete-public-access-block --account-id $ACCOUNT_ID
```

### Install Python pip (Lambda Account Only)
Run in Lambda account CloudShell:

```bash
# Install pip for Python 3
sudo yum install -y python3-pip

# Verify installation
pip3 --version
```

### Install Terraform in AWS CloudShell
Run these commands in both AWS account CloudShells:

```bash
# Download Terraform
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip

# Unzip
unzip terraform_1.6.6_linux_amd64.zip

# Move to bin directory
mkdir -p ~/bin
mv terraform ~/bin/

# Add to PATH (persists in CloudShell)
echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# Verify installation
terraform version
```

### Clone Repository
```bash
git clone https://github.com/eyalestrin/amazon-vpc-lattice.git
cd amazon-vpc-lattice
```

### Install PostgreSQL Client (RDS Account Only)
Run these commands in the RDS AWS account CloudShell:

```bash
# Install PostgreSQL client
sudo yum install -y postgresql15

# Verify installation
psql --version
```

## Get Account IDs Before Deployment

### Lambda Account (Account 1)
Run in Lambda account CloudShell:
```bash
# Get lambda_account_id
aws sts get-caller-identity --query Account --output text
# Save this value - you'll need it for rds/terraform.tfvars -> lambda_account_id
```

### RDS Account (Account 2)
Run in RDS account CloudShell:
```bash
# Get rds_account_id
aws sts get-caller-identity --query Account --output text
# Save this value - you'll need it for lambda/terraform.tfvars -> rds_account_id
```

**IMPORTANT**: Make sure to use the ACTUAL account IDs from the AWS CLI commands above, not the example values in terraform.tfvars.example files.

## Deployment Steps

### 1. Deploy Lambda Account (Account 1)
```bash
cd lambda
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with:
# - rds_account_id = "<value from RDS account>"
terraform init
terraform plan
terraform apply
```

**Get lambda_service_network_arn:**
```bash
aws vpc-lattice list-service-networks --query 'items[?name==`lambda-rds-network`].arn' --output text
# Save this value - you'll need it for rds/terraform.tfvars -> lambda_service_network_arn
```

**Update Lambda to share service network via RAM:**
```bash
# Still in Lambda account
terraform apply
# This shares the service network with RDS account via AWS RAM
```

**Accept RAM share in RDS account:**
```bash
# In RDS account CloudShell
RAM_INVITATION=$(aws ram get-resource-share-invitations --query 'resourceShareInvitations[0].resourceShareInvitationArn' --output text)
aws ram accept-resource-share-invitation --resource-share-invitation-arn $RAM_INVITATION

# Verify acceptance
aws ram get-resource-shares --resource-owner OTHER-ACCOUNTS --query 'resourceShares[0].status' --output text
# Should show: ACTIVE
```

### 2. Deploy RDS Account (Account 2)
```bash
cd ../rds
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with:
# - lambda_account_id = "<value from Lambda account>"
# - lambda_service_network_arn = "<value from step 1>"
# CRITICAL: Use the ACTUAL ARN from step 1, not the example placeholder
# CRITICAL: Ensure db_username = "dbadmin" (not "admin" - it's a reserved word)
terraform init
terraform plan
terraform apply
```

**Get RDS variables:**
```bash
# Get db_secret_arn (exclude deleted secrets)
aws secretsmanager list-secrets --query 'SecretList[?starts_with(Name, `rds-db-credentials`) && !DeletedDate].ARN' --output text
# Save this value - you'll need it for lambda/terraform.tfvars -> db_secret_arn

# Get rds_vpc_lattice_service_arn
aws vpc-lattice list-services --query 'items[?name==`rds-postgres-service`].arn' --output text
# Save this value - you'll need it for lambda/terraform.tfvars -> rds_vpc_lattice_service_arn
```

### 3. Get VPC Lattice Endpoint and Update Lambda
```bash
# In RDS account - get VPC Lattice endpoint
terraform output vpc_lattice_endpoint
# Copy this endpoint (e.g., rds-postgres-service-xxxxx.yyyyy.vpc-lattice-svcs.us-east-1.on.aws)
```

```bash
# In Lambda account
cd ../lambda

# Edit terraform.tfvars and add:
# vpc_lattice_endpoint = "rds-postgres-service-xxxxx.yyyyy.vpc-lattice-svcs.us-east-1.on.aws"

# Apply Terraform to update Lambda with VPC Lattice endpoint
terraform apply

# Get API endpoint and update HTML
API_ENDPOINT=$(terraform output -raw api_endpoint)
sed "s|API_ENDPOINT_PLACEHOLDER|$API_ENDPOINT|g" query.html > query_updated.html

# Upload updated HTML to S3
BUCKET_NAME=$(terraform output -raw website_url | cut -d'/' -f3 | cut -d'.' -f1)
aws s3 cp query_updated.html s3://$BUCKET_NAME/index.html --content-type text/html

# Verify upload
echo "Website URL: $(terraform output -raw website_url)"
```

### 4. Load Sample Data
```bash
# In RDS account
cd rds

# Create table
aws lambda invoke \
  --function-name rds-proxy-lambda \
  --cli-binary-format raw-in-base64-out \
  --payload '{"body":"{\"sql\":\"CREATE TABLE IF NOT EXISTS transactions (transaction_id INTEGER PRIMARY KEY, description VARCHAR(30))\"}"}' \
  response.json
cat response.json

# Insert sample data (20 transactions)
aws lambda invoke \
  --function-name rds-proxy-lambda \
  --cli-binary-format raw-in-base64-out \
  --payload '{"body":"{\"sql\":\"INSERT INTO transactions (transaction_id, description) VALUES (10234567, '\''Online purchase at Amazon'\''),(20456789, '\''Gas station payment'\''),(30678901, '\''Grocery store checkout'\''),(40891234, '\''Restaurant dinner bill'\''),(50123456, '\''Monthly subscription fee'\''),(60345678, '\''ATM cash withdrawal'\''),(70567890, '\''Electric utility payment'\''),(80789012, '\''Coffee shop purchase'\''),(90901234, '\''Movie ticket booking'\''),(11223344, '\''Pharmacy medication buy'\''),(22334455, '\''Hotel accommodation charge'\''),(33445566, '\''Airline ticket purchase'\''),(44556677, '\''Car rental service'\''),(55667788, '\''Mobile phone bill payment'\''),(66778899, '\''Internet service charge'\''),(77889900, '\''Gym membership renewal'\''),(88990011, '\''Book store purchase'\''),(99001122, '\''Pet supplies shopping'\''),(12345678, '\''Home insurance premium'\''),(23456789, '\''Streaming service fee'\'')\"}'}' \
  response.json
cat response.json

# Test query
aws lambda invoke \
  --function-name rds-proxy-lambda \
  --cli-binary-format raw-in-base64-out \
  --payload '{"body":"{\"transaction_id\":\"10234567\"}"}' \
  response.json
cat response.json
```

## Access
- Website: Check `website_url` output from Lambda deployment
- Lambda: Invoke via AWS Console or CLI

## Troubleshooting

If you see "Description: Not found" or errors, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed debugging steps.

**Quick Checks:**
```bash
# In RDS account - verify data is loaded
aws lambda invoke --function-name rds-proxy-lambda \
  --payload '{"body":"{\"transaction_id\":\"10234567\"}"}' response.json
cat response.json

# In Lambda account - verify VPC Lattice endpoint is set
aws lambda get-function-configuration --function-name transaction-rds-reader \
  --query 'Environment.Variables.VPC_LATTICE_ENDPOINT'

# In Lambda account - verify HTML has API endpoint (not placeholder)
BUCKET_NAME=$(cd lambda && terraform output -raw website_url | cut -d'/' -f3 | cut -d'.' -f1)
aws s3 cp s3://$BUCKET_NAME/index.html - | grep -v API_ENDPOINT_PLACEHOLDER
```

## Security Features
- AWS Secrets Manager stores RDS credentials securely
- Cross-account secret access with resource policies
- IAM authentication enabled for RDS
- VPC Lattice with AWS_IAM authentication
- Lambda execution role with least privilege
- No hardcoded credentials in code or environment variables

## Git Commands

**Push changes to repository:**
```bash
# Stage all changes
git add .

# Commit with message
git commit -m "Your commit message here"

# Push to GitHub
git push
```

**Check status:**
```bash
git status
```

## Files
- `lambda/` - Lambda function, S3 website, VPC Lattice network
- `rds/` - PostgreSQL RDS, Secrets Manager, VPC Lattice service
- `lambda/query.html` - Static website UI
- `lambda/lambda_rds_reader.py` - Lambda function code
- `rds/transactions_data.sql` - Sample data for PostgreSQL
