output "api_endpoint" {
  description = "URL base del API del dashboard."
  value       = aws_apigatewayv2_api.dashboard.api_endpoint
}

output "metrics_url_example" {
  description = "Ejemplo de llamada al endpoint de métricas."
  value       = "${aws_apigatewayv2_api.dashboard.api_endpoint}/metrics?user_id=1"
}

output "lambda_function_name" {
  value = aws_lambda_function.metrics.function_name
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "db_secret_arn" {
  description = "Secreto con las credenciales de RDS (generado por RDS)."
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}
