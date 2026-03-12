data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name_prefix = "${var.project_name}-${replace(var.aws_region, "-", "")}" 
  sns_message = jsonencode({
    email  = var.candidate_email
    source = "ECS"
    region = var.aws_region
    repo   = var.repo_url
  })
}

resource "aws_dynamodb_table" "greeting_logs" {
  name = "${local.name_prefix}-GreetingLogs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "request_id"

  attribute {
    name = "request_id"
    type = "S"
  }
}

resource "aws_cloudwatch_log_group" "greeter" {
  name = "/aws/lambda/${local.name_prefix}-greeter"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "dispatcher" {
  name = "/aws/lambda/${local.name_prefix}-dispatcher"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "ecs" {
  name = "/ecs/${local.name_prefix}-dispatcher"
  retention_in_days = 7
}

resource "aws_iam_role" "greeter_lambda_role" {
  name = "${local.name_prefix}-greeter-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "greeter_logs" {
  role = aws_iam_role.greeter_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "greeter_inline" {
  name = "${local.name_prefix}-greeter-inline"
  role = aws_iam_role.greeter_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.greeting_logs.arn
      },
      {
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = var.verification_topic_arn
      }
    ]
  })
}

resource "aws_iam_role" "dispatcher_lambda_role" {
  name = "${local.name_prefix}-dispatcher-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dispatcher_logs" {
  role = aws_iam_role.dispatcher_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${local.name_prefix}-ecs-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${local.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_publish_sns" {
  name = "${local.name_prefix}-ecs-publish-sns"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["sns:Publish"]
      Resource = var.verification_topic_arn
    }]
  })
}

resource "aws_iam_role_policy" "dispatcher_inline" {
  name = "${local.name_prefix}-dispatcher-inline"
  role = aws_iam_role.dispatcher_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ecs:RunTask"]
        Resource = [aws_ecs_task_definition.dispatcher.arn]
      },
      {
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
 aws_iam_role.ecs_task_execution_role.arn,
 aws_iam_role.ecs_task_role.arn
        ]
      }
    ]
  })
}

resource "aws_vpc" "this" {
  cidr_block  = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id= aws_vpc.this.id
  cidr_block     = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id= aws_vpc.this.id
  cidr_block     = "10.20.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ecs" {
  name = "${local.name_prefix}-ecs-sg"
  description = "ECS egress-only security group"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"
}

resource "aws_ecs_task_definition" "dispatcher" {
  family = "${local.name_prefix}-dispatcher-task"
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = 256
  memory = 512
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name = "awscli"
      image = "public.ecr.aws/aws-cli/aws-cli:2.15.45"
      essential = true
      command = [
        "sh",
        "-c",
        "aws sns publish --region us-east-1 --topic-arn ${var.verification_topic_arn} --message '${replace(local.sns_message, "'", "\\'")}' && echo done"
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
 awslogs-group = aws_cloudwatch_log_group.ecs.name
 awslogs-region = var.aws_region
 awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "archive_file" "greeter_zip" {
  type = "zip"
  source_file = "${path.module}/../../lambdas/greeter/app.py"
  output_path = "${path.module}/../../build/${var.aws_region}-greeter.zip"
}

resource "archive_file" "dispatcher_zip" {
  type = "zip"
  source_file = "${path.module}/../../lambdas/dispatcher/app.py"
  output_path = "${path.module}/../../build/${var.aws_region}-dispatcher.zip"
}

resource "aws_lambda_function" "greeter" {
  function_name = "${local.name_prefix}-greeter"
  role = aws_iam_role.greeter_lambda_role.arn
  handler = "app.lambda_handler"
  runtime = "python3.12"
  timeout = 10
  filename= archive_file.greeter_zip.output_path
  source_code_hash = archive_file.greeter_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.greeting_logs.name
      SNS_TOPIC_ARN = var.verification_topic_arn
      CANDIDATE_EMAIL = var.candidate_email
      REPO_URL = var.repo_url
      EXECUTING_REGION = var.aws_region
    }
  }

  depends_on = [aws_cloudwatch_log_group.greeter]
}

resource "aws_lambda_function" "dispatcher" {
  function_name = "${local.name_prefix}-dispatcher"
  role = aws_iam_role.dispatcher_lambda_role.arn
  handler = "app.lambda_handler"
  runtime = "python3.12"
  timeout = 20
  filename = archive_file.dispatcher_zip.output_path
  source_code_hash = archive_file.dispatcher_zip.output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER_ARN = aws_ecs_cluster.this.arn
      ECS_TASK_DEFINITION_ARN = aws_ecs_task_definition.dispatcher.arn
      ECS_SUBNET_IDS= join(",", [aws_subnet.public_a.id, aws_subnet.public_b.id])
      ECS_SECURITY_GROUP_ID  = aws_security_group.ecs.id
      EXECUTING_REGION = var.aws_region
    }
  }

  depends_on = [aws_cloudwatch_log_group.dispatcher]
}

resource "aws_apigatewayv2_api" "this" {
  name = "${local.name_prefix}-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id = aws_apigatewayv2_api.this.id
  name = "cognito-jwt"
  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [var.cognito_client_id]
    issuer = var.cognito_issuer_url
  }
}

resource "aws_apigatewayv2_integration" "greet" {
  api_id = aws_apigatewayv2_api.this.id
  integration_type = "AWS_PROXY"
  integration_uri = aws_lambda_function.greeter.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "dispatch" {
  api_id = aws_apigatewayv2_api.this.id
  integration_type = "AWS_PROXY"
  integration_uri = aws_lambda_function.dispatcher.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "greet" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "GET /greet"
  target    = "integrations/${aws_apigatewayv2_integration.greet.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "dispatch" {
  api_id = aws_apigatewayv2_api.this.id
  route_key = "POST /dispatch"
  target = "integrations/${aws_apigatewayv2_integration.dispatch.id}"
  authorization_type = "JWT"
  authorizer_id = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.this.id
  name = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_greet" {
  statement_id  = "AllowExecutionFromAPIGatewayGreet"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.greeter.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_dispatch" {
  statement_id  = "AllowExecutionFromAPIGatewayDispatch"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dispatcher.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
