# AWS Lambda: controlador de la lógica Cache-Aside.
# El paquete se genera con ./build.sh antes de `terraform apply`.

# En AWS Academy (Learner Lab) no se pueden crear roles IAM: se reutiliza LabRole
# con existing_lambda_role_name = "LabRole". Fuera de Academy se crea un rol propio.
locals {
  create_lambda_role = var.existing_lambda_role_name == null
  lambda_role_arn    = local.create_lambda_role ? aws_iam_role.lambda[0].arn : data.aws_iam_role.existing[0].arn
}

data "aws_iam_role" "existing" {
  count = local.create_lambda_role ? 0 : 1
  name  = var.existing_lambda_role_name
}

resource "aws_iam_role" "lambda" {
  count = local.create_lambda_role ? 1 : 0
  name  = "${local.name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Logs en CloudWatch + creación de ENIs para correr dentro de la VPC.
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  count      = local.create_lambda_role ? 1 : 0
  role       = aws_iam_role.lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_db_secret" {
  count = local.create_lambda_role ? 1 : 0
  name  = "read-db-secret"
  role  = aws_iam_role.lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_db_instance.main.master_user_secret[0].secret_arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}-metrics"
  retention_in_days = 14
}

resource "aws_lambda_function" "metrics" {
  function_name = "${local.name}-metrics"
  role          = local.lambda_role_arn
  runtime       = "python3.12"
  architectures = ["arm64"]
  handler       = "handler.lambda_handler"

  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      REDIS_HOST        = aws_elasticache_replication_group.redis.primary_endpoint_address
      REDIS_PORT        = "6379"
      REDIS_TLS         = "true"
      CACHE_TTL_SECONDS = tostring(var.cache_ttl_seconds)
      DB_HOST           = aws_db_instance.main.address
      DB_PORT           = tostring(aws_db_instance.main.port)
      DB_NAME           = var.db_name
      DB_SECRET_ARN     = aws_db_instance.main.master_user_secret[0].secret_arn
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_vpc_endpoint.secretsmanager,
  ]
}
