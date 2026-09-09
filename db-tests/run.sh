#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

failed=0
for f in db-tests/*.test.sql; do
  echo "=== $f"
  if docker exec -i bmt-test psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q < "$f"; then
    echo "PASS $f"
  else
    echo "FAIL $f"
    failed=1
  fi
done
exit "$failed"
