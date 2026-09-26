# Amazon ElastiCache (Redis): capa en memoria del patrón Cache-Aside.
# La Lambda guarda aquí las métricas con TTL (SETEX).

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.name}-cache-subnets"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_parameter_group" "redis" {
  name   = "${local.name}-redis7"
  family = "redis7"

  # Si la memoria se llena, expulsa primero las llaves con TTL menos usadas.
  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${local.name}-redis"
  description          = "Cache de metricas del dashboard (Cache-Aside + TTL)"

  engine               = "redis"
  engine_version       = var.cache_engine_version
  node_type            = var.cache_node_type
  num_cache_clusters   = 1
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.redis.name

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  automatic_failover_enabled = false
  apply_immediately          = true
}
