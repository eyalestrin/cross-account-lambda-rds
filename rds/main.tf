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
  name_prefix = "rds-postgres-lattice-"
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

  lifecycle {
    create_before_destroy = true
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

# Proxy Lambda IAM role
resource "aws_iam_role" "proxy_lambda" {
  name = "rds-proxy-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "proxy_lambda_vpc" {
  role       = aws_iam_role.proxy_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Proxy Lambda layer
resource "null_resource" "proxy_psycopg2_layer" {
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/proxy_layer/python
      pip3 download psycopg2-binary --platform manylinux2014_x86_64 --python-version 3.11 --only-binary=:all: -d ${path.module}/proxy_layer/
      cd ${path.module}/proxy_layer && unzip -o *.whl -d python/ && rm *.whl
    EOT
  }
  triggers = {
    always_run = timestamp()
  }
}

data "archive_file" "proxy_psycopg2_layer" {
  type        = "zip"
  source_dir  = "${path.module}/proxy_layer"
  output_path = "${path.module}/proxy_psycopg2_layer.zip"
  depends_on  = [null_resource.proxy_psycopg2_layer]
}

resource "aws_lambda_layer_version" "proxy_psycopg2" {
  filename            = data.archive_file.proxy_psycopg2_layer.output_path
  layer_name          = "proxy-psycopg2-layer"
  compatible_runtimes = ["python3.11"]
  source_code_hash    = data.archive_file.proxy_psycopg2_layer.output_base64sha256
}

# Proxy Lambda function
data "archive_file" "proxy_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_proxy.py"
  output_path = "${path.module}/lambda_proxy.zip"
}

resource "aws_lambda_function" "proxy" {
  filename         = data.archive_file.proxy_lambda.output_path
  function_name    = "rds-proxy-lambda"
  role            = aws_iam_role.proxy_lambda.arn
  handler         = "lambda_proxy.lambda_handler"
  runtime         = "python3.11"
  source_code_hash = data.archive_file.proxy_lambda.output_base64sha256
  timeout         = 30

  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.rds.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_db_instance.postgres.address
      DB_NAME     = var.db_name
      DB_USER     = var.db_username
      DB_PASSWORD = random_password.db_password.result
    }
  }

  layers = [aws_lambda_layer_version.proxy_psycopg2.arn]
}

# VPC Lattice target group for proxy Lambda
resource "aws_vpclattice_target_group" "rds" {
  name = "rds-postgres-tg"
  type = "LAMBDA"
  config {
    lambda_event_structure_version = "V2"
  }
}

resource "aws_vpclattice_target_group_attachment" "proxy" {
  target_group_identifier = aws_vpclattice_target_group.rds.id
  target {
    id = aws_lambda_function.proxy.arn
  }
}

resource "aws_lambda_permission" "vpc_lattice" {
  statement_id  = "AllowVPCLatticeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proxy.function_name
  principal     = "vpc-lattice.amazonaws.com"
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
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.rds.id
      }
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

output "vpc_lattice_endpoint" {
  value = aws_vpclattice_service.rds.dns_entry[0].domain_name
}

output "vpc_lattice_service_id" {
  value = aws_vpclattice_service.rds.id
}
