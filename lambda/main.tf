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
    null = {
      source  = "hashicorp/null"
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

# VPC Endpoint for VPC Lattice (cheaper than NAT Gateway)
resource "aws_vpc_endpoint" "vpc_lattice" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.aws_region}.vpc-lattice"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.default.ids
  security_group_ids  = [aws_security_group.lambda.id]
  private_dns_enabled = true
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

# Share service network with RDS account using RAM
resource "aws_ram_resource_share" "lattice" {
  name                      = "vpc-lattice-share"
  allow_external_principals = true
}

resource "aws_ram_resource_association" "lattice" {
  resource_arn       = aws_vpclattice_service_network.main.arn
  resource_share_arn = aws_ram_resource_share.lattice.arn
}

resource "aws_ram_principal_association" "lattice" {
  principal          = var.rds_account_id
  resource_share_arn = aws_ram_resource_share.lattice.arn
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
        Action = "vpc-lattice-svcs:Invoke"
        Resource = "*"
      }
    ]
  })
}

# Create psycopg2 layer
resource "null_resource" "psycopg2_layer" {
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/layer/python
      pip3 download psycopg2-binary --platform manylinux2014_x86_64 --python-version 3.11 --only-binary=:all: -d ${path.module}/layer/
      cd ${path.module}/layer && unzip -o *.whl -d python/ && rm *.whl
    EOT
  }
  triggers = {
    always_run = timestamp()
  }
}

data "archive_file" "psycopg2_layer" {
  type        = "zip"
  source_dir  = "${path.module}/layer"
  output_path = "${path.module}/psycopg2_layer.zip"
  depends_on  = [null_resource.psycopg2_layer]
}

resource "aws_lambda_layer_version" "psycopg2" {
  filename            = data.archive_file.psycopg2_layer.output_path
  layer_name          = "psycopg2-layer"
  compatible_runtimes = ["python3.11"]
  source_code_hash    = data.archive_file.psycopg2_layer.output_base64sha256
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
      VPC_LATTICE_ENDPOINT = var.vpc_lattice_endpoint
    }
  }

  layers = [aws_lambda_layer_version.psycopg2.arn]
}

# API Gateway for Lambda
resource "aws_apigatewayv2_api" "lambda" {
  name          = "transaction-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id      = aws_apigatewayv2_api.lambda.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id             = aws_apigatewayv2_api.lambda.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.rds_reader.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "lambda" {
  api_id    = aws_apigatewayv2_api.lambda.id
  route_key = "POST /query"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rds_reader.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

output "website_url" {
  value = "http://${aws_s3_bucket_website_configuration.website.website_endpoint}"
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.lambda.api_endpoint
}

output "lambda_function_arn" {
  value = aws_lambda_function.rds_reader.arn
}

output "service_network_arn" {
  value = aws_vpclattice_service_network.main.arn
}
