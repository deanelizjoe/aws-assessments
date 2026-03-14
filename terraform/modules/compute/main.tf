# terraform/modules/compute/main.tf
# Regional compute stack: API Gateway, Lambda x2, DynamoDB, ECS Fargate.
# Deployed identically to every region by passing region-specific variables.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

locals {
  # SNS topic owned by Unleash — cross-account publish only
  # unleash_sns_arn = "arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic"
  unleash_sns_arn = "arn:aws:sns:ap-southeast-2:661722818235:Candi-Veri"

  name_prefix = "${var.project_name}-${var.aws_region}"
}

# ══════════════════════════════════════════════════════════════════════════════
# IAM — Lambda execution roles
# ══════════════════════════════════════════════════════════════════════════════

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ── Greeter Lambda role ──────────────────────────────────────────────────────
resource "aws_iam_role" "greeter" {
  name               = "${local.name_prefix}-greeter-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "greeter_policy" {
  # CloudWatch Logs
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${local.name_prefix}-greeter*"]
  }

  # DynamoDB — regional table only
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem"]
    resources = [aws_dynamodb_table.greeting_logs.arn]
  }

  # SNS publish to Unleash verification topic (cross-account)
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [local.unleash_sns_arn]
  }
}

resource "aws_iam_role_policy" "greeter" {
  name   = "greeter-policy"
  role   = aws_iam_role.greeter.id
  policy = data.aws_iam_policy_document.greeter_policy.json
}

# ── Dispatcher Lambda role ───────────────────────────────────────────────────
resource "aws_iam_role" "dispatcher" {
  name               = "${local.name_prefix}-dispatcher-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "dispatcher_policy" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${local.name_prefix}-dispatcher*"]
  }

  # ECS RunTask (scoped to the regional cluster/task-def)
  statement {
    effect  = "Allow"
    actions = ["ecs:RunTask"]
    resources = [
      aws_ecs_task_definition.publisher.arn,
      # Allow any revision of this task definition
      replace(aws_ecs_task_definition.publisher.arn, "/:\\d+$/", ":*"),
    ]
  }

  # iam:PassRole — required to hand the task role to ECS
  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ecs_task_execution.arn, aws_iam_role.ecs_task.arn]
  }
}

resource "aws_iam_role_policy" "dispatcher" {
  name   = "dispatcher-policy"
  role   = aws_iam_role.dispatcher.id
  policy = data.aws_iam_policy_document.dispatcher_policy.json
}

# ──────────────────────────────────────────────
# ECS task execution role (pull image, write logs)
# ──────────────────────────────────────────────
resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.name_prefix}-ecs-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_exec_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ── ECS task role (what the container can DO) ────────────────────────────────
resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

data "aws_iam_policy_document" "ecs_task_policy" {
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [local.unleash_sns_arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/ecs/${local.name_prefix}*"]
  }
}

resource "aws_iam_role_policy" "ecs_task" {
  name   = "ecs-task-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_policy.json
}

# ══════════════════════════════════════════════════════════════════════════════
# DynamoDB
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_dynamodb_table" "greeting_logs" {
  name         = "${local.name_prefix}-GreetingLogs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "RequestId"

  attribute {
    name = "RequestId"
    type = "S"
  }

  # Encryption at rest with AWS-managed key
  server_side_encryption {
    enabled = true
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  tags = var.tags
}

# ══════════════════════════════════════════════════════════════════════════════
# Lambda — package + deploy
# ══════════════════════════════════════════════════════════════════════════════

data "archive_file" "greeter" {
  type        = "zip"
  source_dir  = "${path.root}/../../../lambdas/greeter"
  output_path = "${path.module}/builds/greeter.zip"
}

data "archive_file" "dispatcher" {
  type        = "zip"
  source_dir  = "${path.root}/../../../lambdas/dispatcher"
  output_path = "${path.module}/builds/dispatcher.zip"
}

# CloudWatch log groups (explicit — prevents orphan groups on destroy)
resource "aws_cloudwatch_log_group" "greeter" {
  name              = "/aws/lambda/${local.name_prefix}-greeter"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "dispatcher" {
  name              = "/aws/lambda/${local.name_prefix}-dispatcher"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_lambda_function" "greeter" {
  function_name    = "${local.name_prefix}-greeter"
  role             = aws_iam_role.greeter.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.greeter.output_path
  source_code_hash = data.archive_file.greeter.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      DYNAMODB_TABLE  = aws_dynamodb_table.greeting_logs.name
      UNLEASH_SNS_ARN = local.unleash_sns_arn
      AWS_REGION_NAME = var.aws_region
      REPO_URL        = var.repo_url
      AUTHOR_EMAIL    = var.author_email
    }
  }

  depends_on = [aws_cloudwatch_log_group.greeter]
  tags       = var.tags
}

resource "aws_lambda_function" "dispatcher" {
  function_name    = "${local.name_prefix}-dispatcher"
  role             = aws_iam_role.dispatcher.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.dispatcher.output_path
  source_code_hash = data.archive_file.dispatcher.output_base64sha256
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      ECS_CLUSTER_ARN     = aws_ecs_cluster.main.arn
      ECS_TASK_DEF_ARN    = aws_ecs_task_definition.publisher.arn
      ECS_SUBNET_ID       = aws_subnet.public.id
      ECS_SECURITY_GRP_ID = aws_security_group.ecs_task.id
      AWS_REGION_NAME     = var.aws_region
    }
  }

  depends_on = [aws_cloudwatch_log_group.dispatcher]
  tags       = var.tags
}

# Lambda permissions — allow API Gateway to invoke
resource "aws_lambda_permission" "greeter" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.greeter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*/greet"
}

resource "aws_lambda_permission" "dispatcher" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dispatcher.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*/dispatch"
}

# ══════════════════════════════════════════════════════════════════════════════
# API Gateway v2 (HTTP API)
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Authorization", "Content-Type"]
    max_age       = 300
  }

  tags = var.tags
}

# JWT Authorizer — validates tokens against the centralised Cognito pool
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-authorizer"

  jwt_configuration {
    audience = [var.cognito_client_id]
    issuer   = "https://cognito-idp.us-east-1.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

# Integrations
resource "aws_apigatewayv2_integration" "greeter" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.greeter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "dispatcher" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dispatcher.invoke_arn
  payload_format_version = "2.0"
}

# Routes
resource "aws_apigatewayv2_route" "greet" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /greet"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.greeter.id}"
}

resource "aws_apigatewayv2_route" "dispatch" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /dispatch"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.dispatcher.id}"
}

# Stage — auto-deploy
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
    })
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigateway/${local.name_prefix}"
  retention_in_days = 14
  tags              = var.tags
}

# ══════════════════════════════════════════════════════════════════════════════
# VPC — minimal public-only setup (avoids NAT Gateway charges)
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "${local.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${local.name_prefix}-igw" })
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "${local.name_prefix}-public" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(var.tags, { Name = "${local.name_prefix}-rt-public" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security group — ECS tasks: allow outbound HTTPS only (SNS/ECS API calls)
resource "aws_security_group" "ecs_task" {
  name        = "${local.name_prefix}-ecs-task-sg"
  description = "ECS Fargate task - outbound HTTPS only"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS to internet (SNS publish, ECR pull)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-ecs-task-sg" })
}

# ══════════════════════════════════════════════════════════════════════════════
# ECS Fargate
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}-publisher"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_ecs_task_definition" "publisher" {
  family                   = "${local.name_prefix}-publisher"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "publisher"
      image     = "amazon/aws-cli:latest"
      essential = true

      # Build the SNS publish command at task-definition time using known values.
      # Region and email are injected via environment variables so the same
      # task definition pattern works identically across regions.
      command = [
        "sns", "publish",
        "--region", "ap-southeast-2",
        "--topic-arn", local.unleash_sns_arn,
        "--message", jsonencode({
          email  = var.author_email
          source = "ECS"
          region = var.aws_region
          repo   = var.repo_url
        })
      ]

      environment = [
        { name = "AWS_DEFAULT_REGION", value = var.aws_region }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "publisher"
        }
      }
    }
  ])

  tags = var.tags
}
