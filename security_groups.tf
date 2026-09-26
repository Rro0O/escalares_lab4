# Principio de mínimo privilegio en red:
#   Lambda -> Redis (6379), Lambda -> PostgreSQL (5432), Lambda -> Secrets Manager (443)

resource "aws_security_group" "lambda" {
  name        = "${local.name}-lambda-sg"
  description = "Lambda del dashboard de metricas"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-lambda-sg" }
}

resource "aws_vpc_security_group_egress_rule" "lambda_all" {
  security_group_id = aws_security_group.lambda.id
  description       = "Salida dentro de la VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "RDS PostgreSQL - solo accesible desde la Lambda"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-rds-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_lambda" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL desde Lambda"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.lambda.id
}

resource "aws_security_group" "redis" {
  name        = "${local.name}-redis-sg"
  description = "ElastiCache Redis - solo accesible desde la Lambda"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-redis-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_lambda" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Redis desde Lambda"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.lambda.id
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name}-vpce-sg"
  description = "VPC Interface Endpoints"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-vpce-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_lambda" {
  security_group_id            = aws_security_group.vpc_endpoints.id
  description                  = "HTTPS desde Lambda"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.lambda.id
}
