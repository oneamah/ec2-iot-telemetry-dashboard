data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "archive_file" "metrics_ingest" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

data "archive_file" "metrics_api" {
  type        = "zip"
  source_file = "${path.module}/lambda_api_function.py"
  output_path = "${path.module}/lambda_api_function.zip"
}

data "aws_iot_endpoint" "data" {
  endpoint_type = "iot:Data-ATS"
}

locals {
  metrics_topic        = "${var.project_name}/ec2/metrics"
  thing_name           = "${var.project_name}-ec2"
  topic_rule_name      = replace("${var.project_name}_metrics_to_lambda", "-", "_")
  iot_topic_arn        = "arn:aws:iot:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:topic/${local.metrics_topic}"
  frontend_bucket_name = lower("${replace(var.project_name, "_", "-")}-web-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}")
  common_tags = {
    Project = var.project_name
    Example = "ec2-iot-telemetry"
  }
}

resource "aws_vpc" "telemetry" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.telemetry.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-subnet"
  })
}

resource "aws_internet_gateway" "telemetry" {
  vpc_id = aws_vpc.telemetry.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.telemetry.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.telemetry.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Outbound access for EC2 metrics publisher"
  vpc_id      = aws_vpc.telemetry.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ec2-sg"
  })
}

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ec2_iot_publish" {
  name = "${var.project_name}-ec2-iot-publish"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "iot:Publish"
        ]
        Effect   = "Allow"
        Resource = local.iot_topic_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_dynamodb_table" "metrics" {
  name         = "${var.project_name}-metrics"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "thing_name"
  range_key    = "ts"

  attribute {
    name = "thing_name"
    type = "S"
  }

  attribute {
    name = "ts"
    type = "N"
  }

  tags = local.common_tags
}

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-ingest-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${var.project_name}-lambda-dynamodb"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Query"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.metrics.arn
      }
    ]
  })
}

resource "aws_lambda_function" "metrics_ingest" {
  function_name    = "${var.project_name}-metrics-ingest"
  filename         = data.archive_file.metrics_ingest.output_path
  source_code_hash = data.archive_file.metrics_ingest.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda.arn
  timeout          = 30

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.metrics.name
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_function" "metrics_api" {
  function_name    = "${var.project_name}-metrics-api"
  filename         = data.archive_file.metrics_api.output_path
  source_code_hash = data.archive_file.metrics_api.output_base64sha256
  handler          = "lambda_api_function.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda.arn
  timeout          = 30

  environment {
    variables = {
      TABLE_NAME          = aws_dynamodb_table.metrics.name
      THING_NAME          = aws_iot_thing.ec2_metrics_source.name
      DEFAULT_QUERY_LIMIT = tostring(var.api_default_query_limit)
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "metrics-api"
  })
}

resource "aws_iot_thing" "ec2_metrics_source" {
  name = local.thing_name

  attributes = {
    source = "ec2"
  }
}

resource "aws_iot_topic_rule" "metrics_to_lambda" {
  name        = local.topic_rule_name
  enabled     = true
  sql         = "SELECT * FROM '${local.metrics_topic}'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.metrics_ingest.arn
  }
}

resource "aws_lambda_permission" "allow_iot" {
  statement_id  = "AllowExecutionFromIotRule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.metrics_ingest.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.metrics_to_lambda.arn
}

resource "aws_apigatewayv2_api" "metrics" {
  name          = "${var.project_name}-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["content-type"]
    allow_methods = ["GET", "OPTIONS"]
    allow_origins = var.api_allowed_origins
    max_age       = 300
  }

  tags = merge(local.common_tags, {
    Purpose = "frontend-api"
  })
}

resource "aws_apigatewayv2_integration" "metrics_lambda" {
  api_id                 = aws_apigatewayv2_api.metrics.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.metrics_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "metrics_get" {
  api_id    = aws_apigatewayv2_api.metrics.id
  route_key = "GET /metrics"
  target    = "integrations/${aws_apigatewayv2_integration.metrics_lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.metrics.id
  name        = "$default"
  auto_deploy = true

  tags = merge(local.common_tags, {
    Purpose = "default-stage"
  })
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowExecutionFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.metrics_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.metrics.execution_arn}/*/*"
}

resource "aws_s3_bucket" "frontend" {
  bucket = local.frontend_bucket_name

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-frontend"
    Purpose = "static-website"
  })
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend_public_read" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPublicRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

resource "aws_instance" "telemetry" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/cloud-config.yaml", {
    aws_region                 = data.aws_region.current.region
    iot_data_endpoint          = "https://${data.aws_iot_endpoint.data.endpoint_address}"
    iot_topic                  = local.metrics_topic
    telemetry_interval_seconds = var.telemetry_interval_seconds
    thing_name                 = aws_iot_thing.ec2_metrics_source.name
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.common_tags, {
    Name      = "${var.project_name}-ec2"
    ThingName = aws_iot_thing.ec2_metrics_source.name
  })
}