#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p db-tests/drift

docker exec -i bmt-test psql -U postgres -d bmt -At -v ON_ERROR_STOP=1 \
  < db-tests/drift-check.sql > db-tests/drift/local.txt

echo "wrote db-tests/drift/local.txt ($(wc -l < db-tests/drift/local.txt) rows)"
echo "now run the same six queries against production and save to db-tests/drift/prod.txt,"
echo "then: diff db-tests/drift/prod.txt db-tests/drift/local.txt"
