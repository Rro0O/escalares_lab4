# API Gateway (HTTP API): punto de entrada del dashboard.
#   GET /metrics?user_id=<id>  -> Lambda (Cache-Aside)

resource "aws_apigatewayv2_api" "dashboard" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.cors_allow_origins
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_integration" "metrics" {
  api_id                 = aws_apigatewayv2_api.dashboard.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.metrics.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_metrics" {
  api_id    = aws_apigatewayv2_api.dashboard.id
  route_key = "GET /metrics"
  target    = "integrations/${aws_apigatewayv2_integration.metrics.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.dashboard.id
  name        = "$default"
  auto_deploy = true

  # Sin throttling propio: se usa el límite por defecto de la cuenta/región de
  # API Gateway (miles de req/s), para poder estresar RDS en las pruebas de
  # carga. Riesgo: sin este límite, un pico de tráfico ya no se frena en el
  # borde del API y puede llegar sin control hasta RDS.
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.metrics.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.dashboard.execution_arn}/*/*"
}
