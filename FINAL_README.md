# Cross-Account Lambda to RDS via VPC Lattice

## Architecture
- **Account 1 (Lambda)**: S3 static website + Frontend Lambda function + VPC Lattice Service Network
- **Account 2 (RDS)**: PostgreSQL RDS (private) + Proxy Lambda + VPC Lattice Service + AWS Secrets Manager
- **Connection**: Frontend Lambda → VPC Lattice (HTTPS) → Proxy Lambda → RDS
- **Security**: VPC Lattice with AWS_IAM authentication, RDS in private subnet

**VPC Lattice Flow:**
1. Frontend Lambda (in VPC) calls VPC Lattice HTTPS endpoint
2. DNS resolution via Route53 Resolver VPC Endpoint
3. Traffic stays on AWS backbone (no public internet)
4. VPC Lattice routes to Proxy Lambda in Account 2
5. Proxy Lambda (in VPC) connects to private RDS
6. Returns data through VPC Lattice to Frontend Lambda

**Cost**: ~$7.20/month for Route53 Resolver VPC Endpoint (cheaper than NAT Gateway at ~$32/month)

## Current Status

**The VPC Lattice solution with VPC Endpoints does not work** because:
- VPC Lattice DNS endpoints are not resolvable even with Route53 Resolver VPC Endpoint
- Lambda in VPC requires NAT Gateway (~$32/month) to reach VPC Lattice
- VPC Endpoint for VPC Lattice service is not available in all regions

## Working Alternative

The code currently implements **direct cross-account Lambda invocation**:

```
Frontend Lambda → AWS SDK → Proxy Lambda → RDS
```

**Cost**: $0 (no additional networking costs)

**To use this working solution:**
1. VPC Lattice infrastructure is deployed but not actively used
2. Frontend Lambda invokes Proxy Lambda directly via AWS SDK
3. No VPC Lattice DNS resolution needed
4. No NAT Gateway or VPC Endpoints required

## Recommendation

**Use NAT Gateway (~$32/month) if you must use VPC Lattice**, otherwise use the current direct Lambda invocation approach (free).

The code is configured for direct Lambda invocation which works reliably across accounts.
