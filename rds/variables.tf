variable "aws_region" {
  description = "AWS region for RDS deployment"
  type        = string
  default     = "us-east-1"
}

variable "lambda_account_id" {
  description = "AWS account ID where Lambda function is deployed. Get with: aws sts get-caller-identity --query Account --output text (run in Lambda account)"
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "transactions_db"
}

variable "db_username" {
  description = "Master username for PostgreSQL database"
  type        = string
  default     = "admin"
}

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GB for RDS"
  type        = number
  default     = 20
}

variable "lambda_service_network_arn" {
  description = "VPC Lattice service network ARN from Lambda account. Get with: aws vpc-lattice list-service-networks --query 'items[?name==`lambda-rds-network`].arn' --output text"
  type        = string
}
