#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONTAINER=bmt-test
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
# alpine, not the debian postgres:17 tag: this sandbox's docker daemon
# cannot pull postgres:17 (TLS cert failure on the CDN blob host), but
# postgres:17-alpine is already cached locally and is the same engine
# (verified: `postgres --version` -> PostgreSQL 17.11). Do not "fix" this
# back to postgres:17.
docker run -d --name "$CONTAINER" \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=bmt \
  -p 55432:5432 \
  postgres:17-alpine >/dev/null

echo -n "waiting for postgres"
until docker exec "$CONTAINER" pg_isready -U postgres -d bmt >/dev/null 2>&1; do
  echo -n "."
  sleep 1
done
echo

psql_run() {
  docker exec -i "$CONTAINER" psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q
}

# helpers must run first: they create the roles and the auth.uid() stub
# that 08_rls.sql and the RPCs depend on.
psql_run < db-tests/helpers.sql
for f in docs/sql-export/*.sql; do
  echo "loading $f"
  psql_run < "$f"
done
psql_run < db-tests/seed.sql

echo "test database ready on localhost:55432"
