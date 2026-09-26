"""Lambda del Dashboard de Métricas (patrón Cache-Aside con TTL).

Flujo:
  1. Busca la llave metrics:daily_summary:<user_id> en ElastiCache.
  2. Cache Hit  -> devuelve el JSON guardado.
  3. Cache Miss -> ejecuta las agregaciones en RDS, guarda el resultado con
     TTL (SETEX) y lo devuelve.

Invocación directa (no expuesta en API Gateway) para preparar la BD:
  aws lambda invoke --function-name <fn> --payload '{"action":"init_db"}' out.json
"""

import json
import logging
import os
import ssl
import time
from decimal import Decimal
from pathlib import Path

import boto3
import pg8000.native
import redis

logger = logging.getLogger()
logger.setLevel(logging.INFO)

CACHE_TTL_SECONDS = int(os.environ.get("CACHE_TTL_SECONDS", "300"))
CACHE_KEY = "metrics:daily_summary:{user_id}"
GB = 1024 ** 3

BASE_DIR = Path(__file__).parent
RDS_CA_BUNDLE = BASE_DIR / "rds-ca-bundle.pem"

# Conexiones reutilizadas entre invocaciones del mismo contenedor.
_redis = None
_db_credentials = None


def _get_redis():
    global _redis
    if _redis is None:
        _redis = redis.Redis(
            host=os.environ["REDIS_HOST"],
            port=int(os.environ.get("REDIS_PORT", "6379")),
            ssl=os.environ.get("REDIS_TLS", "true") == "true",
            socket_timeout=2,
            socket_connect_timeout=2,
            decode_responses=True,
        )
    return _redis


def _get_db_credentials():
    global _db_credentials
    if _db_credentials is None:
        secret = boto3.client("secretsmanager").get_secret_value(
            SecretId=os.environ["DB_SECRET_ARN"]
        )
        _db_credentials = json.loads(secret["SecretString"])
    return _db_credentials


def _connect_db():
    creds = _get_db_credentials()
    return pg8000.native.Connection(
        user=creds["username"],
        password=creds["password"],
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        database=os.environ["DB_NAME"],
        ssl_context=ssl.create_default_context(cafile=str(RDS_CA_BUNDLE)),
        timeout=10,
    )


# --- Consultas de agregación (costosas) ---------------------------------------

SQL_STORAGE_BY_PROVIDER = """
    SELECT p.name, COALESCE(SUM(o.size_bytes), 0)
    FROM buckets b
    JOIN providers p ON p.id = b.provider_id
    LEFT JOIN objects o ON o.bucket_id = b.id
    WHERE b.user_id = :user_id
    GROUP BY p.name
    ORDER BY p.name
"""

SQL_BANDWIDTH_MONTH = """
    SELECT direction, COALESCE(SUM(bytes), 0)
    FROM traffic_logs
    WHERE user_id = :user_id
      AND logged_at >= date_trunc('month', now())
    GROUP BY direction
"""

SQL_COST_ESTIMATE = """
    SELECT pl.name,
           pl.base_fee_usd,
           pl.price_per_gb_storage,
           pl.price_per_gb_egress,
           COALESCE((SELECT SUM(o.size_bytes)
                     FROM objects o JOIN buckets b ON b.id = o.bucket_id
                     WHERE b.user_id = u.id), 0) AS storage_bytes,
           COALESCE((SELECT SUM(t.bytes)
                     FROM traffic_logs t
                     WHERE t.user_id = u.id
                       AND t.direction = 'egress'
                       AND t.logged_at >= date_trunc('month', now())), 0) AS egress_bytes
    FROM users u
    JOIN plans pl ON pl.id = u.plan_id
    WHERE u.id = :user_id
"""

SQL_OBJECTS_PER_BUCKET = """
    SELECT b.id, b.name, p.name, COUNT(o.id)
    FROM buckets b
    JOIN providers p ON p.id = b.provider_id
    LEFT JOIN objects o ON o.bucket_id = b.id
    WHERE b.user_id = :user_id AND b.active
    GROUP BY b.id, b.name, p.name
    ORDER BY b.id
"""


def _gb(value):
    return round(float(value) / GB, 3)


def compute_metrics(user_id):
    con = _connect_db()
    try:
        storage = con.run(SQL_STORAGE_BY_PROVIDER, user_id=user_id)
        bandwidth = dict(con.run(SQL_BANDWIDTH_MONTH, user_id=user_id))
        cost_rows = con.run(SQL_COST_ESTIMATE, user_id=user_id)
        buckets = con.run(SQL_OBJECTS_PER_BUCKET, user_id=user_id)
    finally:
        con.close()

    if not cost_rows:
        return None

    plan, base_fee, price_storage, price_egress, storage_bytes, egress_bytes = cost_rows[0]
    storage_cost = Decimal(storage_bytes) / GB * price_storage
    egress_cost = Decimal(egress_bytes) / GB * price_egress

    return {
        "user_id": user_id,
        "storage_by_provider": [
            {"provider": name, "gb": _gb(total)} for name, total in storage
        ],
        "bandwidth_current_month": {
            "ingress_gb": _gb(bandwidth.get("ingress", 0)),
            "egress_gb": _gb(bandwidth.get("egress", 0)),
        },
        "estimated_cost": {
            "plan": plan,
            "base_fee_usd": float(base_fee),
            "storage_usd": round(float(storage_cost), 2),
            "egress_usd": round(float(egress_cost), 2),
            "total_usd": round(float(base_fee + storage_cost + egress_cost), 2),
        },
        "objects_per_bucket": [
            {"bucket_id": bid, "bucket": bname, "provider": pname, "objects": count}
            for bid, bname, pname, count in buckets
        ],
        "generated_at": int(time.time()),
    }


# --- Cache-Aside ---------------------------------------------------------------

def get_metrics(user_id):
    key = CACHE_KEY.format(user_id=user_id)
    cache = _get_redis()

    try:
        cached = cache.get(key)
    except redis.RedisError:
        # Si la caché falla, degradamos a leer directo de RDS.
        logger.exception("Error leyendo ElastiCache; se consultará RDS")
        cached = None

    if cached is not None:
        return json.loads(cached), "HIT"

    metrics = compute_metrics(user_id)
    if metrics is None:
        return None, "MISS"

    try:
        cache.setex(key, CACHE_TTL_SECONDS, json.dumps(metrics))
    except redis.RedisError:
        logger.exception("Error escribiendo en ElastiCache")

    return metrics, "MISS"


def _response(status, body, headers=None):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", **(headers or {})},
        "body": json.dumps(body),
    }


def _init_db():
    con = _connect_db()
    try:
        for filename in ("schema.sql", "seed.sql"):
            raw = (BASE_DIR / "sql" / filename).read_text()
            # Quitar las líneas de comentario ANTES de separar por ";": un
            # comentario puede contener un ";" dentro de comillas y partirlo
            # a la mitad si se separa primero.
            code = "\n".join(
                l for l in raw.splitlines() if not l.strip().startswith("--")
            )
            for statement in code.split(";"):
                statement = statement.strip()
                if statement:
                    con.run(statement)
    finally:
        con.close()
    return {"status": "ok"}


def lambda_handler(event, context):
    if event.get("action") == "init_db":
        return _init_db()

    params = event.get("queryStringParameters") or {}
    try:
        user_id = int(params.get("user_id", ""))
    except ValueError:
        return _response(400, {"error": "user_id (entero) es requerido"})

    start = time.perf_counter()
    metrics, cache_status = get_metrics(user_id)
    elapsed_ms = round((time.perf_counter() - start) * 1000, 1)
    logger.info(json.dumps({"user_id": user_id, "cache": cache_status, "ms": elapsed_ms}))

    if metrics is None:
        return _response(404, {"error": f"usuario {user_id} no encontrado"})

    return _response(
        200,
        metrics,
        {"X-Cache": cache_status, "X-Response-Time-Ms": str(elapsed_ms)},
    )
