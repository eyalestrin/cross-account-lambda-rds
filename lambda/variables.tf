variable "aws_region" {
  description = "AWS region for Lambda and S3 deployment"
  type        = string
  default     = "us-east-1"
}

variable "rds_account_id" {
  description = "AWS account ID where RDS PostgreSQL is deployed. Get with: aws sts get-caller-identity --query Account --output text (run in RDS account)"
  type        = string
}

variable "rds_endpoint" {
  description = "RDS PostgreSQL endpoint hostname"
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "transactions_db"
}

variable "db_username" {
  description = "PostgreSQL database username"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "PostgreSQL database password from RDS account"
  type        = string
  sensitive   = true
}

variable "rds_vpc_lattice_service_arn" {
  description = "VPC Lattice service ARN from RDS account for cross-account access. Get with: aws vpc-lattice list-services --query 'items[?name==`rds-postgres-service`].arn' --output text"
  type        = string
}
