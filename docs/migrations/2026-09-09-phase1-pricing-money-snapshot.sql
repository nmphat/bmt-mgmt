-- Money-parity snapshot for 2026-09-09-phase1-pricing.sql.
--
-- Run every query below and save the output BEFORE applying the migration,
-- then run them again AFTER and diff as plain text. Same ordering, same
-- columns -- the two outputs must be byte-identical.
--
-- Query 1 is per-member, not per-session: the new court_cost branch
-- changes how court money is *split between the members present in each
-- interval*, not just each session's total, so a session-level sum could
-- hide one member gaining while another loses the same amount. Query 1 is
-- the row-level evidence for that axis (this is the shape the task brief
-- specified). Query 2 is a fast scalar sanity check on top of it. Query 3
-- reads session_costs_snapshot, the frozen ledger of already-finalized/paid
-- amounts -- no statement in the migration touches that table, and this
-- query is what proves it wasn't touched.
--
-- Suggested invocation (psql), so the two runs are directly diffable:
--   psql ... -t -A -F',' -f docs/migrations/2026-09-09-phase1-pricing-money-snapshot.sql > before.csv
--   ...apply the migration...
--   psql ... -t -A -F',' -f docs/migrations/2026-09-09-phase1-pricing-money-snapshot.sql > after.csv
--   diff before.csv after.csv   # expect: no output
--
-- From the Supabase SQL editor instead (no easy file-diff there): run
-- query 1b before and after and compare its single fingerprint value
-- instead of eyeballing every row. Keep query 1's row-level form too --
-- the fingerprint says *whether* something moved, the rows say *where*.

-- Query 1: every member's final_total for every live session.
SELECT s.id, c.member_id, c.final_total
FROM sessions s
CROSS JOIN LATERAL calculate_session_costs(s.id) c
WHERE s.deleted_at IS NULL
ORDER BY s.id, c.member_id;

-- Query 1b: the same rows collapsed into one comparable fingerprint.
SELECT md5(string_agg(
         session_id::text || ':' || member_id::text || ':' || final_total::text,
         ',' ORDER BY session_id, member_id
       )) AS fingerprint
FROM (
  SELECT s.id AS session_id, c.member_id, c.final_total
  FROM sessions s
  CROSS JOIN LATERAL calculate_session_costs(s.id) c
  WHERE s.deleted_at IS NULL
) rows;

-- Query 2: grand total across all live sessions -- a single number, the
-- fastest possible parity check before diffing the full per-member list.
SELECT COALESCE(SUM(c.final_total), 0) AS grand_total
FROM sessions s
CROSS JOIN LATERAL calculate_session_costs(s.id) c
WHERE s.deleted_at IS NULL;

-- Query 3: the frozen ledger. Same shape as docs/migrations/README.md's
-- own phase0 snapshot query -- reused, not reinvented.
SELECT count(*) AS snapshots,
       sum(paid_amount) AS total_paid,
       sum(final_amount) AS total_final,
       count(*) FILTER (WHERE status = 'paid') AS paid_rows,
       count(*) FILTER (WHERE status = 'partial') AS partial_rows,
       count(*) FILTER (WHERE status = 'pending') AS pending_rows
FROM session_costs_snapshot;
