-- Money-parity snapshot for 2026-09-09-phase1-pricing.sql.
--
-- Run query 1 and save the output BEFORE applying the migration, then run
-- it again AFTER and diff the two files as plain text. Same ordering
-- (by session id), same columns, one row per live session -- the two
-- outputs must be byte-identical. This migration adds columns with
-- defaults chosen so no existing session's cost changes (see the
-- migration's own comments); this snapshot is the proof.
--
-- Suggested invocation, so the two runs are directly diffable:
--   psql ... -t -A -F',' -f docs/migrations/2026-09-09-phase1-pricing-money-snapshot.sql > before.csv
--   ...apply the migration...
--   psql ... -t -A -F',' -f docs/migrations/2026-09-09-phase1-pricing-money-snapshot.sql > after.csv
--   diff before.csv after.csv   # expect: no output

-- Query 1: per-session total (sum of every member's final_total for that
-- session), one row per live session, ordered by session id.
SELECT s.id AS session_id,
       COALESCE(SUM(c.final_total), 0) AS session_total
FROM sessions s
LEFT JOIN LATERAL calculate_session_costs(s.id) c ON true
WHERE s.deleted_at IS NULL
GROUP BY s.id
ORDER BY s.id;

-- Query 2: grand total across all live sessions -- a single number, the
-- fastest possible parity check before diffing the full per-session list.
SELECT COALESCE(SUM(c.final_total), 0) AS grand_total
FROM sessions s
CROSS JOIN LATERAL calculate_session_costs(s.id) c
WHERE s.deleted_at IS NULL;
