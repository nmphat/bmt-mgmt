-- Soft-delete cancelled sessions + cleanup RPCs + daily garbage collector

ALTER TABLE public.sessions
ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone;

CREATE INDEX IF NOT EXISTS idx_sessions_deleted_at ON public.sessions (deleted_at);
CREATE INDEX IF NOT EXISTS idx_sessions_status_deleted_at ON public.sessions (status, deleted_at);

CREATE OR REPLACE VIEW public.view_attendance_log AS
SELECT
  s.title AS session_name,
  m.display_name AS member_name,
  i.idx AS interval_index,
  i.start_time AS interval_time,
  p.is_present,
  p.id AS presence_id,
  p.member_id,
  p.interval_id
FROM public.interval_presence p
JOIN public.session_intervals i ON i.id = p.interval_id
JOIN public.sessions s ON s.id = i.session_id
JOIN public.members m ON m.id = p.member_id
WHERE s.deleted_at IS NULL;

CREATE OR REPLACE VIEW public.view_member_debt_summary AS
SELECT
  m.id AS member_id,
  m.display_name,
  m.user_id AS auth_user_id,
  count(scs.id) AS unpaid_session_count,
  sum((scs.final_amount - scs.paid_amount)) AS total_debt
FROM public.session_costs_snapshot scs
JOIN public.members m ON m.id = scs.member_id
JOIN public.sessions s ON s.id = scs.session_id
WHERE scs.status <> 'paid'::public.payment_status
  AND s.deleted_at IS NULL
GROUP BY m.id, m.display_name, m.user_id
HAVING sum((scs.final_amount - scs.paid_amount)) > 0::numeric;

CREATE OR REPLACE VIEW public.view_member_session_details AS
SELECT
  scs.id AS snapshot_id,
  scs.member_id,
  scs.session_id,
  s.title AS session_title,
  s.start_time,
  (s.start_time)::date AS session_date,
  scs.final_amount,
  scs.court_fee_amount,
  scs.shuttle_fee_amount,
  scs.extra_fee_amount,
  scs.paid_amount,
  (scs.final_amount - scs.paid_amount) AS remaining_amount,
  scs.status,
  scs.payment_code,
  scs.created_at
FROM public.session_costs_snapshot scs
JOIN public.sessions s ON s.id = scs.session_id
WHERE s.deleted_at IS NULL;

CREATE OR REPLACE VIEW public.view_session_summary AS
SELECT
  s.id,
  s.title,
  s.start_time,
  s.end_time,
  (s.start_time)::date AS session_date,
  s.status,
  s.price_per_hour,
  s.default_court_count,
  COALESCE(s.court_fee_addon, 0::numeric) AS court_fee_addon,
  (
    COALESCE(
      (
        SELECT sum((si.active_court_count::numeric * (s.price_per_hour / 2::numeric)))
        FROM public.session_intervals si
        WHERE si.session_id = s.id
      ),
      0::numeric
    ) + COALESCE(s.court_fee_addon, 0::numeric)
  ) AS total_court_cost,
  s.shuttle_fee_total,
  COALESCE(
    (
      SELECT sum(ex.amount)
      FROM public.session_extra_charges ex
      WHERE ex.session_id = s.id
    ),
    0::numeric
  ) AS total_extra_cost,
  (
    SELECT count(*)
    FROM public.session_registrations r
    WHERE r.session_id = s.id
  ) AS total_registrations,
  (
    SELECT count(*)
    FROM public.session_intervals si
    WHERE si.session_id = s.id
  ) AS total_intervals,
  COALESCE(
    (
      SELECT sum(sc.paid_amount)
      FROM public.session_costs_snapshot sc
      WHERE sc.session_id = s.id
    ),
    0::numeric
  ) AS total_collected
FROM public.sessions s
WHERE s.deleted_at IS NULL;

CREATE OR REPLACE FUNCTION public.get_session_delete_impact(p_session_id uuid)
RETURNS TABLE(
  session_id uuid,
  registrations_count integer,
  intervals_count integer,
  presence_count integer,
  court_bookings_count integer,
  extra_charges_count integer,
  snapshots_count integer,
  payments_count integer
)
LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    s.id,
    (
      SELECT count(*)::integer
      FROM public.session_registrations r
      WHERE r.session_id = s.id
    ) AS registrations_count,
    (
      SELECT count(*)::integer
      FROM public.session_intervals i
      WHERE i.session_id = s.id
    ) AS intervals_count,
    (
      SELECT count(*)::integer
      FROM public.interval_presence p
      JOIN public.session_intervals i ON i.id = p.interval_id
      WHERE i.session_id = s.id
    ) AS presence_count,
    (
      SELECT count(*)::integer
      FROM public.session_court_bookings b
      WHERE b.session_id = s.id
    ) AS court_bookings_count,
    (
      SELECT count(*)::integer
      FROM public.session_extra_charges ex
      WHERE ex.session_id = s.id
    ) AS extra_charges_count,
    (
      SELECT count(*)::integer
      FROM public.session_costs_snapshot sc
      WHERE sc.session_id = s.id
    ) AS snapshots_count,
    (
      SELECT count(*)::integer
      FROM public.session_payments sp
      JOIN public.session_costs_snapshot sc ON sc.id = sp.snapshot_id
      WHERE sc.session_id = s.id
    ) AS payments_count
  FROM public.sessions s
  WHERE s.id = p_session_id
    AND s.deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Session not found or already deleted';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.soft_delete_cancelled_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
  v_status text;
  v_deleted_at timestamp with time zone;
  v_impact RECORD;
BEGIN
  SELECT status::text, deleted_at
  INTO v_status, v_deleted_at
  FROM public.sessions
  WHERE id = p_session_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Session not found';
  END IF;

  IF v_deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'session_id', p_session_id,
      'deleted', false,
      'message', 'already_deleted'
    );
  END IF;

  IF v_status <> 'cancelled' THEN
    RAISE EXCEPTION 'Only cancelled sessions can be deleted';
  END IF;

  SELECT * INTO v_impact
  FROM public.get_session_delete_impact(p_session_id)
  LIMIT 1;

  IF COALESCE(v_impact.payments_count, 0) > 0 THEN
    RAISE EXCEPTION 'Cancelled session still has payment records';
  END IF;

  -- Session-lock trigger only allows mutations while status='open'.
  UPDATE public.sessions
  SET status = 'open',
      updated_at = now()
  WHERE id = p_session_id;

  DELETE FROM public.interval_presence p
  USING public.session_intervals i
  WHERE p.interval_id = i.id
    AND i.session_id = p_session_id;

  DELETE FROM public.session_payments sp
  USING public.session_costs_snapshot sc
  WHERE sp.snapshot_id = sc.id
    AND sc.session_id = p_session_id;

  DELETE FROM public.session_costs_snapshot
  WHERE session_id = p_session_id;

  DELETE FROM public.session_extra_charges
  WHERE session_id = p_session_id;

  DELETE FROM public.session_registrations
  WHERE session_id = p_session_id;

  DELETE FROM public.session_court_bookings
  WHERE session_id = p_session_id;

  DELETE FROM public.session_intervals
  WHERE session_id = p_session_id;

  UPDATE public.sessions
    SET status = 'cancelled',
      deleted_at = now(),
      updated_at = now()
  WHERE id = p_session_id;

  RETURN jsonb_build_object(
    'session_id', p_session_id,
    'deleted', true,
    'registrations_count', COALESCE(v_impact.registrations_count, 0),
    'intervals_count', COALESCE(v_impact.intervals_count, 0),
    'presence_count', COALESCE(v_impact.presence_count, 0),
    'court_bookings_count', COALESCE(v_impact.court_bookings_count, 0),
    'extra_charges_count', COALESCE(v_impact.extra_charges_count, 0),
    'snapshots_count', COALESCE(v_impact.snapshots_count, 0),
    'payments_count', COALESCE(v_impact.payments_count, 0)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.soft_delete_cancelled_sessions_bulk(p_session_ids uuid[])
RETURNS TABLE(session_id uuid, deleted boolean, message text)
LANGUAGE plpgsql
AS $function$
DECLARE
  v_session_id uuid;
BEGIN
  IF p_session_ids IS NULL OR array_length(p_session_ids, 1) IS NULL THEN
    RETURN;
  END IF;

  IF array_length(p_session_ids, 1) > 50 THEN
    RAISE EXCEPTION 'Bulk delete limit exceeded (max 50 sessions per request)';
  END IF;

  FOREACH v_session_id IN ARRAY p_session_ids LOOP
    BEGIN
      PERFORM public.soft_delete_cancelled_session(v_session_id);
      RETURN QUERY SELECT v_session_id, true, 'ok'::text;
    EXCEPTION WHEN OTHERS THEN
      RETURN QUERY SELECT v_session_id, false, SQLERRM;
    END;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.gc_soft_deleted_sessions(
  p_older_than interval DEFAULT interval '30 days'
)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
  v_session_id uuid;
  v_deleted_count integer := 0;
BEGIN
  FOR v_session_id IN
    SELECT s.id
    FROM public.sessions s
    WHERE s.deleted_at IS NOT NULL
      AND s.deleted_at < now() - p_older_than
  LOOP
    DELETE FROM public.interval_presence p
    USING public.session_intervals i
    WHERE p.interval_id = i.id
      AND i.session_id = v_session_id;

    DELETE FROM public.session_payments sp
    USING public.session_costs_snapshot sc
    WHERE sp.snapshot_id = sc.id
      AND sc.session_id = v_session_id;

    DELETE FROM public.session_costs_snapshot
    WHERE session_id = v_session_id;

    DELETE FROM public.session_extra_charges
    WHERE session_id = v_session_id;

    DELETE FROM public.session_registrations
    WHERE session_id = v_session_id;

    DELETE FROM public.session_court_bookings
    WHERE session_id = v_session_id;

    DELETE FROM public.session_intervals
    WHERE session_id = v_session_id;

    DELETE FROM public.sessions
    WHERE id = v_session_id
      AND deleted_at IS NOT NULL
      AND deleted_at < now() - p_older_than;

    v_deleted_count := v_deleted_count + 1;
  END LOOP;

  RETURN v_deleted_count;
END;
$function$;

DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'gc_soft_deleted_sessions_daily';

    PERFORM cron.schedule(
      'gc_soft_deleted_sessions_daily',
      '0 3 * * *',
      $job$SELECT public.gc_soft_deleted_sessions(interval '30 days');$job$
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- Keep migration non-blocking if cron is unavailable.
  NULL;
END;
$do$;