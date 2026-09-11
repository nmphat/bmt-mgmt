-- Migration: fix view_session_summary.total_court_cost to use per-court pricing
-- The view still computed total_court_cost from the legacy formula
-- (active_court_count * price_per_hour / 2) + court_fee_addon,
-- ignoring session_intervals.court_cost. For sessions using per-court pricing,
-- price_per_hour is 0 and court_cost carries the real value.
-- This makes the view match the CASE WHEN logic in calculate_session_costs.

BEGIN;

SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE VIEW public.view_session_summary AS
  SELECT id,
    title,
    start_time,
    end_time,
    (start_time)::date AS session_date,
    status,
    price_per_hour,
    default_court_count,
    COALESCE(court_fee_addon, (0)::numeric) AS court_fee_addon,
    (COALESCE(( SELECT sum(
            CASE
                WHEN si.court_cost > 0 THEN si.court_cost
                ELSE ((si.active_court_count)::numeric * (s.price_per_hour / (2)::numeric))
            END) AS sum
           FROM session_intervals si
          WHERE (si.session_id = s.id)), (0)::numeric) + COALESCE(court_fee_addon, (0)::numeric)) AS total_court_cost,
    shuttle_fee_total,
    COALESCE(( SELECT sum(ex.amount) AS sum
           FROM session_extra_charges ex
          WHERE (ex.session_id = s.id)), (0)::numeric) AS total_extra_cost,
    ( SELECT count(*) AS count
           FROM session_registrations r
          WHERE (r.session_id = s.id)) AS total_registrations,
    ( SELECT count(*) AS count
           FROM session_intervals si
          WHERE (si.session_id = s.id)) AS total_intervals,
    COALESCE(( SELECT sum(sc.paid_amount) AS sum
           FROM session_costs_snapshot sc
          WHERE (sc.session_id = s.id)), (0)::numeric) AS total_collected
   FROM sessions s
  WHERE (s.deleted_at IS NULL);

COMMIT;

-- Rollback: re-create the view from the legacy formula.
-- Not needed here since CREATE OR REPLACE is idempotent and the previous
-- definition is in git history (0f2e89b^:docs/sql-export/05_views.sql).
