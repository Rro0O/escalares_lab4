-- rds_stress.lua
--
-- A diferencia de un user_id real (1-20, cacheable), estos IDs no existen en
-- la base de datos. La Lambda igual corre las 4 consultas de agregación en
-- RDS antes de descubrir que no hay resultados, y como el resultado es
-- vacío NUNCA se guarda en ElastiCache (ver compute_metrics/get_metrics en
-- handler.py). Cada petición golpea RDS, siempre, sin que la caché la frene.
--
-- Úsalo sólo con el throttling de API Gateway desactivado (si no, la mayoría
-- de las peticiones se van a rechazar con 429 antes de llegar a la Lambda).

math.randomseed(os.time())

request = function()
   local user_id = math.random(100000, 999999)
   return wrk.format("GET", "/metrics?user_id=" .. user_id)
end
