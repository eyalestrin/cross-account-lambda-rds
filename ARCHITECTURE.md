# Architecture Overview

## Components

### Lambda Account (Account 1)
- **S3 Bucket**: Hosts static website (query.html)
- **API Gateway**: HTTP API endpoint for frontend
- **Frontend Lambda**: Receives requests from API Gateway, invokes RDS proxy Lambda cross-account
- **IAM Role**: Allows Lambda to invoke function in RDS account

### RDS Account (Account 2)
- **RDS PostgreSQL**: Private database in VPC (db.t3.micro)
- **Proxy Lambda**: Connects to RDS, executes queries
- **Lambda Layer**: psycopg2 for PostgreSQL connectivity
- **Secrets Manager**: Stores RDS credentials
- **Lambda Permission**: Allows Lambda account to invoke proxy Lambda

## Data Flow

```
User Browser
    ↓
S3 Static Website (query.html)
    ↓
API Gateway (HTTPS)
    ↓
Frontend Lambda (Account 1)
    ↓
Cross-Account Lambda Invoke (IAM)
    ↓
Proxy Lambda (Account 2)
    ↓
RDS PostgreSQL (Private)
```

## Security

1. **Cross-Account Access**: IAM-based Lambda invoke (no VPC peering needed)
2. **RDS Isolation**: Private subnet, not publicly accessible
3. **Credentials**: Stored in Secrets Manager, passed via environment variables
4. **API Security**: CORS enabled, API Gateway authentication optional
5. **Least Privilege**: Lambda roles have minimal required permissions

## Cost Estimate

- **RDS db.t3.micro**: ~$15/month
- **Lambda**: Free tier covers most usage
- **API Gateway**: $1 per million requests
- **S3**: Minimal (static website)
- **Secrets Manager**: $0.40/month per secret

**Total**: ~$16-20/month
