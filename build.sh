#!/usr/bin/env bash
# Empaqueta la Lambda en build/lambda.zip (código + dependencias + SQL + CA de RDS).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PKG="$ROOT/build/package"

rm -rf "$ROOT/build"
mkdir -p "$PKG/sql"

python3 -m pip install --quiet -r "$ROOT/lambda/requirements.txt" --target "$PKG"
cp "$ROOT"/lambda/src/*.py "$PKG/"
cp "$ROOT"/sql/*.sql "$PKG/sql/"

# Certificados de RDS para conectarse a PostgreSQL con TLS verificado.
curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
  -o "$PKG/rds-ca-bundle.pem"

(cd "$PKG" && zip -qr "$ROOT/build/lambda.zip" . -x '*__pycache__*')
echo "Paquete generado: build/lambda.zip"
