#!/usr/bin/env bash
set -euo pipefail
#
# Two-sided drift check: the local test bed (built from docs/sql-export/*.sql)
# against production. This script only writes the LOCAL side.
#
# THE ORDERING IS THE WHOLE CONTRACT. db-tests/drift-check.sql is eight queries
# that each return one text column named `row`. psql -At concatenates their
# results into one file with no headers and no separators, so `diff` lines up
# only if production is read with the SAME eight queries in the SAME order:
#
#   1. tables and columns          (pg_class + pg_attribute, public, relkind='r',
#                                   type AND nullability)
#   2. indexes                     (pg_indexes, public)
#   3. policies                    (pg_policies, public, ADMIN_CHECK-normalised)
#   4. functions                   (proname, args, secdef, proconfig, body md5)
#   5. function grants             (anon/authenticated privilege + raw proacl)
#   6. triggers                    (non-internal, schemas public AND auth)
#   7. views                       (pg_get_viewdef, whitespace-collapsed)
#   8. constraints                 (pg_get_constraintdef, whitespace-collapsed)
#
# Queries 7 and 8 and the nullability marker in query 1 are new: views,
# constraints and nullability were all invisible to this check, and all three
# were changed by this branch. THE FORMAT OF QUERY 1 CHANGED, so an older
# db-tests/drift/prod.txt no longer lines up -- regenerate it.
#
# To refresh db-tests/drift/prod.txt, run db-tests/drift-check.sql against
# production AS ONE SCRIPT — do not run the six queries separately and paste
# them back in a different order, and do not sort the file. It is SELECTs only.
#
#   psql "$PROD_URL" -At -v ON_ERROR_STOP=1 \
#     < db-tests/drift-check.sql > db-tests/drift/prod.txt
#
# From the Supabase SQL editor instead: run each of the eight blocks in the
# order above, appending each result's `row` column to the file in turn.
#
# Expected one-sided rows (local has them, production does not): the four
# test-bed helpers are already excluded by queries 4 and 5, but production
# additionally carries the trigger on_auth_user_created on auth.users, which
# query 6 reports and the local bed does not create.

cd "$(dirname "$0")/.."
mkdir -p db-tests/drift

docker exec -i bmt-test psql -U postgres -d bmt -At -v ON_ERROR_STOP=1 \
  < db-tests/drift-check.sql > db-tests/drift/local.txt

echo "wrote db-tests/drift/local.txt ($(wc -l < db-tests/drift/local.txt) rows)"
echo "now run db-tests/drift-check.sql against production AS ONE SCRIPT (queries 1->8,"
echo "same order, unsorted) and save to db-tests/drift/prod.txt, then:"
echo "  diff db-tests/drift/prod.txt db-tests/drift/local.txt"
