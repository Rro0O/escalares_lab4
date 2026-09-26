-- Esquema de la plataforma de almacenamiento multi-nube.
-- Cada sentencia termina en ';' (la Lambda las ejecuta una por una).

CREATE TABLE IF NOT EXISTS providers (
    id   SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS plans (
    id                    SERIAL PRIMARY KEY,
    name                  TEXT NOT NULL UNIQUE,
    base_fee_usd          NUMERIC(10, 2) NOT NULL,
    price_per_gb_storage  NUMERIC(10, 4) NOT NULL,
    price_per_gb_egress   NUMERIC(10, 4) NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
    id      SERIAL PRIMARY KEY,
    email   TEXT NOT NULL UNIQUE,
    plan_id INT  NOT NULL REFERENCES plans (id)
);

CREATE TABLE IF NOT EXISTS buckets (
    id          SERIAL PRIMARY KEY,
    user_id     INT     NOT NULL REFERENCES users (id),
    provider_id INT     NOT NULL REFERENCES providers (id),
    name        TEXT    NOT NULL,
    active      BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS objects (
    id         BIGSERIAL PRIMARY KEY,
    bucket_id  INT         NOT NULL REFERENCES buckets (id),
    size_bytes BIGINT      NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS traffic_logs (
    id        BIGSERIAL PRIMARY KEY,
    user_id   INT         NOT NULL REFERENCES users (id),
    bucket_id INT         NOT NULL REFERENCES buckets (id),
    direction TEXT        NOT NULL CHECK (direction IN ('ingress', 'egress')),
    bytes     BIGINT      NOT NULL,
    logged_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_buckets_user        ON buckets (user_id);
CREATE INDEX IF NOT EXISTS idx_objects_bucket      ON objects (bucket_id);
CREATE INDEX IF NOT EXISTS idx_traffic_user_time   ON traffic_logs (user_id, logged_at);
