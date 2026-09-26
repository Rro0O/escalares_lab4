# Dashboard de Métricas: Cache-Aside con TTL

Infraestructura en Terraform para el proyecto *Dashboard de Métricas*: una Lambda que
sirve métricas de almacenamiento multi-nube (AWS S3, Backblaze B2, Wasabi) usando
**ElastiCache (Redis)** como caché delante de **RDS (PostgreSQL)**.

```
Dashboard ──HTTP──▶ API Gateway ──▶ Lambda ──(1) GET metrics:daily_summary:<user>──▶ ElastiCache Redis
                                      │                     (2) HIT → responde
                                      └──(3) MISS → SQL de agregación ──▶ RDS PostgreSQL
                                           └── SETEX con TTL (300 s) ──▶ ElastiCache
                          (todo dentro de una VPC privada; Secrets Manager vía VPC Endpoint)
```

## Recursos

| Archivo | Contenido |
|---|---|
| `network.tf` | VPC, 2 subnets privadas, VPC Endpoint de Secrets Manager (sin NAT) |
| `security_groups.tf` | Lambda → Redis :6379, Lambda → Postgres :5432, Lambda → VPCE :443 |
| `rds.tf` | RDS PostgreSQL 16, cifrado, privado, contraseña gestionada en Secrets Manager |
| `elasticache.tf` | Redis 7, cifrado en tránsito y en reposo, `maxmemory-policy=volatile-lru` |
| `lambda.tf` | Lambda Python 3.12 (arm64) dentro de la VPC, rol IAM de mínimo privilegio |
| `apigateway.tf` | HTTP API `GET /metrics?user_id=N` con CORS y throttling |

## Métricas (una llave de caché por usuario)

1. Almacenamiento total por proveedor: `SUM(size_bytes) GROUP BY provider`
2. Ancho de banda del mes (ingress/egress): `SUM(bytes)` filtrado por `user_id`
3. Costo estimado: `users JOIN plans` + consumo de almacenamiento y egress
4. Objetos por bucket activo: `COUNT(object_id) GROUP BY bucket_id`

## Despliegue

```bash
./build.sh                      # genera build/lambda.zip
terraform init
terraform apply
```

Crear el esquema y los datos de prueba (RDS es privado, así que lo hace la Lambda):

```bash
aws lambda invoke --function-name "$(terraform output -raw lambda_function_name)" \
  --cli-binary-format raw-in-base64-out --payload '{"action":"init_db"}' /dev/stdout
```

Probar el cache-aside (fíjate en los headers `X-Cache` y `X-Response-Time-Ms`):

```bash
curl -i "$(terraform output -raw api_endpoint)/metrics?user_id=1"   # X-Cache: MISS
curl -i "$(terraform output -raw api_endpoint)/metrics?user_id=1"   # X-Cache: HIT
```

Destruir todo: `terraform destroy`.

## Notas

- El TTL se ajusta con `cache_ttl_seconds` (default 300 s = 5 min).
- Si Redis falla, la Lambda consulta RDS directamente, así que el dashboard sigue respondiendo.
- ElastiCache, RDS y el VPC Endpoint cobran por hora aunque no haya tráfico: es el costo
  "no serverless" que menciona el documento. Ejecuta `terraform destroy` al terminar el laboratorio.
# escalares_lab4
