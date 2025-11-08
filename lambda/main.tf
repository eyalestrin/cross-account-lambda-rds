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

data "aws_availability_zones" "available" {
  state = "available"
}

# NAT Gateway for VPC Lattice access
# Cost: ~$32/month + data transfer

# Public subnet for NAT Gateway
resource "aws_subnet" "public" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = "172.31.255.0/28"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
}

# Private subnets for Lambda
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = "172.31.25${count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

# Internet Gateway (default VPC already has one)
data "aws_internet_gateway" "default" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Route table for public subnet
resource "aws_route_table" "public" {
  vpc_id = data.aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.default.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [data.aws_internet_gateway.default]
}

# Route table for private subnets (Lambda subnets)
resource "aws_route_table" "private" {
  vpc_id = data.aws_vpc.default.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

# Associate private route table with Lambda subnets
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
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
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for VPC Lattice"
  }

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
  depends_on                 = [aws_nat_gateway.main]
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
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      VPC_LATTICE_ENDPOINT = var.vpc_lattice_endpoint
    }
  }
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
