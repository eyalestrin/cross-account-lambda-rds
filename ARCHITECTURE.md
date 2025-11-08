# VPC Lattice Architecture with NAT Gateway

## Complete Flow

```
User Browser
    ↓
S3 Static Website (Account 1)
    ↓
API Gateway (Account 1)
    ↓
Frontend Lambda (Account 1, in VPC)
    ↓
NAT Gateway (Account 1) - ~$32/month
    ↓
Internet (DNS resolution)
    ↓
VPC Lattice Service Network (Account 1)
    ↓ (AWS Backbone - cross-account)
VPC Lattice Service (Account 2)
    ↓
Proxy Lambda (Account 2, in VPC)
    ↓
RDS PostgreSQL (Account 2, private)
```

## Why NAT Gateway is Required

- Lambda in VPC has no internet access by default
- VPC Lattice DNS endpoints require internet connectivity
- NAT Gateway provides outbound internet access
- Traffic to VPC Lattice goes through AWS backbone after DNS resolution

## Cost Breakdown

| Component | Monthly Cost |
|-----------|--------------|
| NAT Gateway | ~$32 |
| Data Transfer (NAT) | ~$0.045/GB |
| Lambda | Pay per invocation |
| RDS db.t3.micro | ~$15 |
| VPC Lattice | Pay per GB processed |
| **Total** | **~$47+/month** |

## Alternative: Direct Lambda Invocation (No VPC Lattice)

```
Frontend Lambda → AWS SDK → Proxy Lambda → RDS
```

**Cost**: ~$15/month (RDS only)
**Savings**: ~$32/month (no NAT Gateway)
