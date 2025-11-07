# Cross-Account Lambda to RDS via VPC Lattice

## Architecture
- **Account 1 (Lambda)**: S3 static website + Lambda function
- **Account 2 (RDS)**: PostgreSQL RDS (publicly accessible) + AWS Secrets Manager
- **Connection**: Lambda connects to RDS public endpoint using credentials from Secrets Manager
- **Security**: AWS Secrets Manager for credential management, SSL/TLS encryption for database connection

**Note**: RDS is publicly accessible to allow cross-account Lambda connection. Use security groups to restrict access.

## Prerequisites

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

### 3. Update Lambda Account
```bash
cd ../lambda
# Edit terraform.tfvars with:
# - db_secret_arn = "<value from step 2>"
# - rds_vpc_lattice_service_arn = "<value from step 2>"
terraform apply

# Get API endpoint
API_ENDPOINT=$(terraform output -raw api_endpoint)

# Update HTML with API endpoint
sed -i "s|API_ENDPOINT_PLACEHOLDER|$API_ENDPOINT|g" query.html

# Upload updated HTML
BUCKET_NAME=$(terraform output -raw website_url | cut -d'/' -f3 | cut -d'.' -f1)
aws s3 cp query.html s3://$BUCKET_NAME/index.html --content-type text/html
```

### 4. Load Sample Data
```bash
cd rds
# Make RDS publicly accessible for data loading
terraform apply
# Wait 2-3 minutes for RDS to become publicly accessible

# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier transactions-db --query 'DBInstances[0].Endpoint.Address' --output text)

# Get password from Secrets Manager (exclude deleted secrets)
SECRET_ARN=$(aws secretsmanager list-secrets --query 'SecretList[?starts_with(Name, `rds-db-credentials`) && !DeletedDate].ARN' --output text)
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id $SECRET_ARN --query SecretString --output text | python3 -c "import sys, json; print(json.load(sys.stdin)['password'])")

# Load data (SSL required)
PGPASSWORD=$DB_PASSWORD psql "host=$RDS_ENDPOINT port=5432 dbname=transactions_db user=dbadmin sslmode=require" -f transactions_data.sql
```

## Access
- Website: Check `website_url` output from Lambda deployment
- Lambda: Invoke via AWS Console or CLI

## Security Features
- AWS Secrets Manager stores RDS credentials securely
- Cross-account secret access with resource policies
- IAM authentication enabled for RDS
- VPC Lattice with AWS_IAM authentication
- Lambda execution role with least privilege
- No hardcoded credentials in code or environment variables

## Files
- `lambda/` - Lambda function, S3 website, VPC Lattice network
- `rds/` - PostgreSQL RDS, Secrets Manager, VPC Lattice service
- `lambda/query.html` - Static website UI
- `lambda/lambda_rds_reader.py` - Lambda function code
- `rds/transactions_data.sql` - Sample data for PostgreSQL
