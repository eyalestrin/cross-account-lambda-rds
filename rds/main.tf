terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Generate random password for RDS
resource "random_password" "db_password" {
  length  = 16
  special = true
}

# RDS security group
resource "aws_security_group" "rds" {
  name        = "rds-postgres-lattice"
  description = "Allow PostgreSQL access via VPC Lattice and CloudShell"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
    description = "Allow from VPC"
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow from CloudShell for data loading"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS subnet group
resource "aws_db_subnet_group" "rds" {
  name       = "rds-postgres-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
}

# Secrets Manager for RDS credentials
resource "aws_secretsmanager_secret" "rds_credentials" {
  name_prefix             = "rds-db-credentials-"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    host     = aws_db_instance.postgres.address
    dbname   = var.db_name
  })
}

# RDS PostgreSQL instance
resource "aws_db_instance" "postgres" {
  identifier             = "transactions-db"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = var.db_instance_class
  allocated_storage      = var.allocated_storage
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  iam_database_authentication_enabled = true
}

# VPC Lattice target group for RDS
resource "aws_vpclattice_target_group" "rds" {
  name = "rds-postgres-tg"
  type = "LAMBDA"
  config {
    lambda_event_structure_version = "V2"
  }
}

# VPC Lattice service
resource "aws_vpclattice_service" "rds" {
  name      = "rds-postgres-service"
  auth_type = "AWS_IAM"
}

resource "aws_vpclattice_listener" "rds" {
  name               = "postgres-listener"
  protocol           = "HTTPS"
  service_identifier = aws_vpclattice_service.rds.id
  port               = 443
  default_action {
    fixed_response {
      status_code = 404
    }
  }
}

# Associate VPC Lattice service with Lambda account's service network
resource "aws_vpclattice_service_network_service_association" "cross_account" {
  service_identifier         = aws_vpclattice_service.rds.id
  service_network_identifier = var.lambda_service_network_arn
}

# VPC Lattice auth policy for cross-account access
resource "aws_vpclattice_auth_policy" "rds" {
  resource_identifier = aws_vpclattice_service.rds.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action   = "vpc-lattice-svcs:Invoke"
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:PrincipalAccount" = var.lambda_account_id
        }
      }
    }]
  })
}

# Secrets Manager resource policy for cross-account access
resource "aws_secretsmanager_secret_policy" "cross_account" {
  secret_arn = aws_secretsmanager_secret.rds_credentials.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowLambdaAccountAccess"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "secretsmanager:GetSecretValue"
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = var.lambda_account_id
        }
      }
    }]
  })
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "rds_arn" {
  value = aws_db_instance.postgres.arn
}

output "vpc_lattice_service_arn" {
  value = aws_vpclattice_service.rds.arn
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.rds_credentials.arn
}
