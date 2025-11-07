terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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

# Random S3 bucket name
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 bucket for static website
resource "aws_s3_bucket" "website" {
  bucket = "transaction-query-${random_string.bucket_suffix.result}"
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id
  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket                  = aws_s3_bucket.website.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.website.arn}/*"
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.website]
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  source       = "${path.module}/query.html"
  content_type = "text/html"
}

# Lambda security group
resource "aws_security_group" "lambda" {
  name        = "lambda-rds-access"
  description = "Allow Lambda to access RDS via VPC Lattice"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# VPC Lattice Service Network Association
resource "aws_vpclattice_service_network_vpc_association" "lambda" {
  vpc_identifier             = data.aws_vpc.default.id
  service_network_identifier = aws_vpclattice_service_network.main.id
  security_group_ids         = [aws_security_group.lambda.id]
}

resource "aws_vpclattice_service_network" "main" {
  name      = "lambda-rds-network"
  auth_type = "AWS_IAM"
}

# Lambda IAM role
resource "aws_iam_role" "lambda" {
  name = "lambda-rds-execution-role"
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

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_rds_iam_auth" {
  name = "rds-iam-auth"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds-db:connect",
          "vpc-lattice:Invoke"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = var.db_secret_arn
      }
    ]
  })
}

# Lambda function
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_rds_reader.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "rds_reader" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "transaction-rds-reader"
  role            = aws_iam_role.lambda.arn
  handler         = "lambda_rds_reader.lambda_handler"
  runtime         = "python3.11"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout         = 30

  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_SECRET_ARN = var.db_secret_arn
    }
  }

  layers = ["arn:aws:lambda:${var.aws_region}:898466741470:layer:psycopg2-py38:1"]
}

output "website_url" {
  value = "http://${aws_s3_bucket_website_configuration.website.website_endpoint}"
}

output "lambda_function_arn" {
  value = aws_lambda_function.rds_reader.arn
}

output "service_network_arn" {
  value = aws_vpclattice_service_network.main.arn
}
