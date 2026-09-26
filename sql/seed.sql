-- Datos de prueba. Idempotente: sólo inserta si las tablas están vacías.

INSERT INTO providers (name)
SELECT unnest(ARRAY['AWS S3', 'Backblaze B2', 'Wasabi'])
WHERE NOT EXISTS (SELECT 1 FROM providers);

INSERT INTO plans (name, base_fee_usd, price_per_gb_storage, price_per_gb_egress)
SELECT * FROM (VALUES
    ('free',     0.00, 0.0300, 0.0900),
    ('pro',     10.00, 0.0200, 0.0500),
    ('business', 50.00, 0.0150, 0.0200)
) AS v
WHERE NOT EXISTS (SELECT 1 FROM plans);

INSERT INTO users (email, plan_id)
SELECT 'user' || g || '@example.com', 1 + (g % 3)
FROM generate_series(1, 20) AS g
WHERE NOT EXISTS (SELECT 1 FROM users);

INSERT INTO buckets (user_id, provider_id, name, active)
SELECT u.id, 1 + (b % 3), 'bucket-' || u.id || '-' || b, (b % 5) <> 0
FROM users u, generate_series(1, 5) AS b
WHERE NOT EXISTS (SELECT 1 FROM buckets);

-- ~200k objetos para que las agregaciones tengan un costo real.
INSERT INTO objects (bucket_id, size_bytes, created_at)
SELECT 1 + floor(random() * (SELECT count(*) FROM buckets))::int,
       (random() * 500 * 1024 * 1024)::bigint,
       now() - (random() * interval '180 days')
FROM generate_series(1, 200000)
WHERE NOT EXISTS (SELECT 1 FROM objects);

INSERT INTO traffic_logs (user_id, bucket_id, direction, bytes, logged_at)
SELECT b.user_id, b.id,
       CASE WHEN random() < 0.6 THEN 'egress' ELSE 'ingress' END,
       (random() * 200 * 1024 * 1024)::bigint,
       now() - (random() * interval '60 days')
FROM generate_series(1, 100000) AS g
JOIN buckets b ON b.id = 1 + (g % (SELECT count(*) FROM buckets))
WHERE NOT EXISTS (SELECT 1 FROM traffic_logs);
