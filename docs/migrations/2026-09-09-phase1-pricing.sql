-- Phase 1 & 2 — per-court pricing + shuttle tube pricing
-- Run once, after 2026-09-09-phase0-security.sql.
--
-- Reviewed against docs/sql-export/{02_tables,03_constraints,04_indexes,
-- 06_functions,08_rls,09_grants}.sql as of commit 2e22461. Every function
-- body below is copied verbatim from 06_functions.sql; every grant/policy/
-- constraint statement is copied verbatim from its export file. Nothing
-- here was re-derived from memory.

BEGIN;

-- The three ADD COLUMNs below take ACCESS EXCLUSIVE on sessions,
-- session_intervals and session_court_bookings and hold it to COMMIT,
-- queuing ahead of new readers while they wait. Fail fast instead of
-- blocking behind one long-running guest SELECT. Run this migration in a
-- quiet window regardless.
SET LOCAL lock_timeout = '5s';

-- 1. Columns. Defaults are chosen so existing rows keep the old behaviour:
--    price_per_hour = 0 -> court_cost = 0 -> calculate_session_costs falls
--    back to the pre-existing formula. No backfill, on purpose: the 53
--    existing sessions must keep producing the exact final_total they
--    produce today. Do not populate price_per_hour, court_cost or
--    shuttle_usage for existing rows.
ALTER TABLE public.session_court_bookings ADD COLUMN IF NOT EXISTS price_per_hour numeric NOT NULL DEFAULT 0;
ALTER TABLE public.session_intervals      ADD COLUMN IF NOT EXISTS court_cost     numeric NOT NULL DEFAULT 0;
ALTER TABLE public.sessions               ADD COLUMN IF NOT EXISTS shuttle_usage  jsonb   NOT NULL DEFAULT '[]'::jsonb;

CREATE INDEX IF NOT EXISTS idx_court_bookings_session ON public.session_court_bookings (session_id);

-- 1b. Time-order guard on court bookings (docs/sql-export/03_constraints.sql).
-- Production data already satisfies this (47 of 47 booking rows, measured),
-- but ADD CONSTRAINT is not idempotent on its own, so guard it to survive a
-- second run of this script.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'session_court_bookings_time_order_check'
      AND conrelid = 'public.session_court_bookings'::regclass
  ) THEN
    ALTER TABLE public.session_court_bookings
      ADD CONSTRAINT session_court_bookings_time_order_check CHECK (end_time > start_time);
  END IF;
END $$;

-- 2. Catalog table.
CREATE TABLE IF NOT EXISTS public.shuttle_types (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name       text NOT NULL,
  tube_price numeric NOT NULL,
  per_tube   integer NOT NULL DEFAULT 12,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.shuttle_types ENABLE ROW LEVEL SECURITY;

-- shuttle_types policies, copied verbatim from docs/sql-export/08_rls.sql.
-- Note the read policy is TO authenticated only (narrowed from anon,
-- authenticated) and named shuttle_types_authenticated_read, not the
-- shuttle_types_public_read name this task's brief used.
DROP POLICY IF EXISTS shuttle_types_public_read ON public.shuttle_types;
DROP POLICY IF EXISTS shuttle_types_authenticated_read ON public.shuttle_types;
CREATE POLICY shuttle_types_authenticated_read ON public.shuttle_types
  AS PERMISSIVE FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS shuttle_types_admin_write ON public.shuttle_types;
CREATE POLICY shuttle_types_admin_write ON public.shuttle_types
  AS PERMISSIVE FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'));

-- 3. Functions. Bodies copied verbatim from docs/sql-export/06_functions.sql.

CREATE OR REPLACE FUNCTION public.refresh_interval_courts(p_session_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
BEGIN
    -- Update lại active_court_count VÀ court_cost cho từng interval thuộc session đó.
    -- active_court_count: đếm số sân phủ interval (hành vi cũ, giữ nguyên).
    -- court_cost: tổng tiền thật của các sân phủ interval, tính theo số giờ overlap.
    --   Buổi cũ có price_per_hour = 0 nên court_cost = 0, và
    --   calculate_session_costs sẽ rơi về công thức cũ.
    UPDATE session_intervals si
    SET active_court_count = (
        SELECT COUNT(*)
        FROM session_court_bookings b
        WHERE b.session_id = p_session_id
          -- Logic Overlap: Booking bắt đầu trước khi Interval kết thúc
          -- VÀ Booking kết thúc sau khi Interval bắt đầu
          AND b.start_time < si.end_time
          AND b.end_time > si.start_time
    ),
    court_cost = COALESCE((
        SELECT SUM(
            b.price_per_hour
            * EXTRACT(epoch FROM (
                LEAST(b.end_time, si.end_time) - GREATEST(b.start_time, si.start_time)
              )) / 3600.0
        )
        FROM session_court_bookings b
        WHERE b.session_id = p_session_id
          AND b.start_time < si.end_time
          AND b.end_time > si.start_time
    ), 0)
    WHERE si.session_id = p_session_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.calculate_session_costs(p_session_id uuid)
 RETURNS TABLE(member_id uuid, display_name text, final_total numeric, total_court_fee numeric, total_shuttle_fee numeric, total_extra_fee numeric, intervals_count integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_court_fee_addon      NUMERIC;
    v_price_per_hour       NUMERIC;
    v_total_shuttle_fee    NUMERIC;
    v_total_court_units    INT := 0;
    v_total_intervals      INT := 0;  -- fallback denominator when court bookings don't overlap
    v_ghost_count          INT;
BEGIN
    -- 1. Load session config
    SELECT s.court_fee_addon, s.price_per_hour, s.shuttle_fee_total
    INTO v_court_fee_addon, v_price_per_hour, v_total_shuttle_fee
    FROM sessions s
    WHERE s.id = p_session_id;

    -- 2. Total court-units (SUM of active_court_count across all intervals)
    SELECT COALESCE(SUM(si.active_court_count), 0),
           COUNT(si.id)
    INTO v_total_court_units, v_total_intervals
    FROM session_intervals si
    WHERE si.session_id = p_session_id;

    -- 3. Count ghost members
    WITH member_presence_counts AS (
        SELECT r.member_id, COUNT(p.id) FILTER (WHERE p.is_present = true) AS presence_count
        FROM session_registrations r
        JOIN session_intervals i ON i.session_id = r.session_id
        LEFT JOIN interval_presence p ON p.interval_id = i.id AND p.member_id = r.member_id
        WHERE r.session_id = p_session_id
        GROUP BY r.member_id
    )
    SELECT COUNT(*) INTO v_ghost_count
    FROM member_presence_counts
    WHERE presence_count = 0;

    -- 4. Compute costs
    RETURN QUERY
    WITH
    ghost_members AS (
        SELECT r.member_id
        FROM session_registrations r
        JOIN session_intervals i ON i.session_id = r.session_id
        LEFT JOIN interval_presence p ON p.interval_id = i.id AND p.member_id = r.member_id
        WHERE r.session_id = p_session_id
        GROUP BY r.member_id
        HAVING COUNT(p.id) FILTER (WHERE p.is_present = true) = 0
    ),

    interval_stats AS (
        SELECT
            i.id AS interval_id,
            i.active_court_count,
            i.court_cost,
            COUNT(p.member_id) FILTER (WHERE p.is_present = true) AS real_present_count
        FROM session_intervals i
        LEFT JOIN interval_presence p ON p.interval_id = i.id
        WHERE i.session_id = p_session_id
        GROUP BY i.id, i.active_court_count, i.court_cost
    ),

    member_interval_costs AS (
        SELECT
            m.id AS mem_id,
            m.display_name,

            -- A. COURT FEE — Option C additive (booking cost + addon)
            CASE
                WHEN (ist.real_present_count + v_ghost_count) > 0 THEN
                    CASE
                        WHEN gm.member_id IS NOT NULL OR p.is_present = true THEN
                            CASE
                                WHEN v_total_court_units > 0 THEN
                                    -- Normal: both booking cost and addon weighted by court-units.
                                    -- booking_cost prefers the real per-booking price when the
                                    -- session has one; sessions created before per-court pricing
                                    -- have court_cost = 0 and fall back to the old formula.
                                    (
                                        CASE
                                            WHEN ist.court_cost > 0 THEN ist.court_cost
                                            ELSE (v_price_per_hour / 2.0) * ist.active_court_count
                                        END
                                        +
                                        (COALESCE(v_court_fee_addon, 0) * ist.active_court_count::numeric / v_total_court_units)
                                    ) / (ist.real_present_count + v_ghost_count)
                                WHEN v_total_intervals > 0 AND COALESCE(v_court_fee_addon, 0) > 0 THEN
                                    -- Fallback: court bookings don't overlap with intervals
                                    -- (e.g. timezone mismatch). Distribute addon equally per interval.
                                    -- price_per_hour booking cost = 0 (no valid court overlap).
                                    (v_court_fee_addon::numeric / v_total_intervals)
                                    / (ist.real_present_count + v_ghost_count)
                                ELSE 0
                            END
                        ELSE 0
                    END
                ELSE 0
            END AS court_cost,

            -- B. SHUTTLE FEE — only real attendees
            CASE
                WHEN ist.real_present_count > 0 AND v_total_court_units > 0 THEN
                    CASE
                        WHEN p.is_present = true THEN
                            (v_total_shuttle_fee * ist.active_court_count::numeric / v_total_court_units)
                            / ist.real_present_count
                        ELSE 0
                    END
                WHEN ist.real_present_count > 0 AND v_total_intervals > 0 THEN
                    -- Fallback for shuttle when no court overlap either
                    CASE
                        WHEN p.is_present = true THEN
                            (v_total_shuttle_fee / v_total_intervals) / ist.real_present_count
                        ELSE 0
                    END
                ELSE 0
            END AS shuttle_cost,

            CASE WHEN p.is_present = true THEN 1 ELSE 0 END AS is_present_flag

        FROM members m
        CROSS JOIN session_intervals i
        JOIN interval_stats ist ON ist.interval_id = i.id
        LEFT JOIN interval_presence p ON p.interval_id = i.id AND p.member_id = m.id
        JOIN session_registrations r ON r.member_id = m.id AND r.session_id = p_session_id
        LEFT JOIN ghost_members gm ON gm.member_id = m.id
        WHERE i.session_id = p_session_id
    ),

    extra_fee_calc AS (
        SELECT ex.member_id, SUM(ex.amount) AS total_extra
        FROM session_extra_charges ex
        WHERE ex.session_id = p_session_id
        GROUP BY ex.member_id
    )

    SELECT
        mic.mem_id,
        mic.display_name,
        COALESCE(CEIL((SUM(mic.court_cost) + SUM(mic.shuttle_cost) + COALESCE(ef.total_extra, 0)) / 1000.0) * 1000, 0) AS final_total,
        COALESCE(SUM(mic.court_cost), 0)   AS total_court_fee,
        COALESCE(SUM(mic.shuttle_cost), 0) AS total_shuttle_fee,
        COALESCE(ef.total_extra, 0)         AS total_extra_fee,
        COALESCE(SUM(mic.is_present_flag), 0)::INT AS intervals_count
    FROM member_interval_costs mic
    LEFT JOIN extra_fee_calc ef ON ef.member_id = mic.mem_id
    GROUP BY mic.mem_id, mic.display_name, ef.total_extra
    ORDER BY mic.display_name ASC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_session_with_bookings(p_title text, p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_price_per_hour numeric, p_shuttle_fee numeric, p_created_by uuid, p_bookings jsonb, p_court_fee_addon numeric DEFAULT 0)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_session_id UUID;
    v_interval_start TIMESTAMPTZ;
    v_interval_end TIMESTAMPTZ;
    v_idx INT := 0;
    v_booking_item JSONB;
BEGIN
    INSERT INTO sessions (
        title, start_time, end_time, price_per_hour, shuttle_fee_total,
        court_fee_addon, created_by, status
    )
    VALUES (
        p_title, p_start_time, p_end_time, p_price_per_hour, p_shuttle_fee,
        p_court_fee_addon, p_created_by, 'open'
    )
    RETURNING id INTO v_session_id;

    v_interval_start := p_start_time;

    WHILE v_interval_start < p_end_time LOOP
        v_interval_end := v_interval_start + INTERVAL '30 minutes';

        IF v_interval_end > p_end_time THEN
            v_interval_end := p_end_time;
        END IF;

        INSERT INTO session_intervals (session_id, start_time, end_time, idx, active_court_count)
        VALUES (v_session_id, v_interval_start, v_interval_end, v_idx, 0);

        v_interval_start := v_interval_end;
        v_idx := v_idx + 1;
    END LOOP;

    IF p_bookings IS NOT NULL AND jsonb_array_length(p_bookings) > 0 THEN
        FOR v_booking_item IN SELECT * FROM jsonb_array_elements(p_bookings)
        LOOP
            INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time, price_per_hour)
            VALUES (
                v_session_id,
                COALESCE(v_booking_item->>'court_name', v_booking_item->>'name', 'Sân 1'),
                (v_booking_item->>'start_time')::TIMESTAMPTZ,
                (v_booking_item->>'end_time')::TIMESTAMPTZ,
                COALESCE((v_booking_item->>'price_per_hour')::numeric, 0)
            );
        END LOOP;
    ELSE
        INSERT INTO session_court_bookings (session_id, start_time, end_time, court_name)
        VALUES (v_session_id, p_start_time, p_end_time, 'Sân 1 (Mặc định)');
    END IF;

    PERFORM refresh_interval_courts(v_session_id);

    RETURN v_session_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_session_court_bookings(p_session_id uuid, p_bookings jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_status TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này';
    END IF;

    SELECT status::text INTO v_status FROM sessions WHERE id = p_session_id;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Không tìm thấy buổi: %', p_session_id;
    END IF;
    IF v_status <> 'open' THEN
        RAISE EXCEPTION 'Không thể sửa sân khi buổi đang ở trạng thái "%".', v_status;
    END IF;

    DELETE FROM session_court_bookings WHERE session_id = p_session_id;

    INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time, price_per_hour)
    SELECT
        p_session_id,
        e->>'court_name',
        (e->>'start_time')::timestamptz,
        (e->>'end_time')::timestamptz,
        COALESCE((e->>'price_per_hour')::numeric, 0)
    FROM jsonb_array_elements(p_bookings) e;

    PERFORM refresh_interval_courts(p_session_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_session_shuttle_usage(p_session_id uuid, p_usage jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_status TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này';
    END IF;

    SELECT status::text INTO v_status FROM sessions WHERE id = p_session_id;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Không tìm thấy buổi: %', p_session_id;
    END IF;
    IF v_status <> 'open' THEN
        RAISE EXCEPTION 'Không thể sửa tiền cầu khi buổi đang ở trạng thái "%".', v_status;
    END IF;

    -- Mỗi phần tử phải có đủ used/tube_price/per_tube và hợp lệ -- thiếu
    -- (NULL) thì SUM() bên dưới sẽ lặng lẽ bỏ qua phần tử đó (đóng góp 0)
    -- trong khi nó vẫn được lưu trong shuttle_usage, làm breakdown và tổng
    -- lệch nhau mà không có tín hiệu gì; used âm thì lặng lẽ trừ tiền;
    -- per_tube = 0 thì NULLIF bên dưới cũng lặng lẽ biến phần tử thành 0.
    -- Từ chối cả ba trước khi ghi.
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_usage) e WHERE e->>'used' IS NULL) THEN
        RAISE EXCEPTION 'Thiếu số lượng ống cầu (used) trong dữ liệu tiền cầu';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_usage) e WHERE e->>'tube_price' IS NULL) THEN
        RAISE EXCEPTION 'Thiếu giá ống cầu (tube_price) trong dữ liệu tiền cầu';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_usage) e WHERE e->>'per_tube' IS NULL) THEN
        RAISE EXCEPTION 'Thiếu số cầu mỗi ống (per_tube) trong dữ liệu tiền cầu';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_usage) e WHERE (e->>'used')::numeric < 0) THEN
        RAISE EXCEPTION 'Số lượng ống cầu (used) không được âm';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_usage) e WHERE (e->>'per_tube')::numeric <= 0) THEN
        RAISE EXCEPTION 'Số cầu mỗi ống (per_tube) phải lớn hơn 0';
    END IF;

    -- Breakdown và tổng tiền được ghi trong cùng một lệnh, nên không có
    -- đường nào để hai giá trị lệch nhau. Tổng được làm tròn một lần, về
    -- nguyên đồng, sau khi cộng hết -- không làm tròn từng phần tử.
    UPDATE sessions
    SET shuttle_usage = p_usage,
        shuttle_fee_total = ROUND(COALESCE((
            SELECT SUM(
                (e->>'tube_price')::numeric
                / NULLIF((e->>'per_tube')::numeric, 0)
                * (e->>'used')::numeric
            )
            FROM jsonb_array_elements(p_usage) e
        ), 0)),
        updated_at = now()
    WHERE id = p_session_id;
END;
$function$;

-- The 7-argument overload (no p_court_fee_addon) is dropped: nothing in
-- src/ binds it any more (src/views/CreateSessionView.vue already calls
-- the 8-argument form with p_court_fee_addon), but it is still live on
-- production. Drop it only after the 8-argument version above exists.
DROP FUNCTION IF EXISTS public.create_session_with_bookings(text, timestamp with time zone, timestamp with time zone, numeric, numeric, uuid, jsonb);

-- 4. Grants for the functions touched above. Copied verbatim from
-- docs/sql-export/09_grants.sql. FROM PUBLIC, anon (not just FROM anon) is
-- required: on Supabase, anon reaches EXECUTE through two independent
-- grants -- PostgreSQL's default grant to PUBLIC and Supabase's own
-- ALTER DEFAULT PRIVILEGES grant directly to anon -- so a single-target
-- revoke leaves the other path open and revokes nothing.

-- refresh_interval_courts: SECURITY DEFINER (writes court_cost to session_intervals).
-- Called by SECURITY INVOKER functions (create_session_with_bookings, recreate_session_intervals,
-- trigger_refresh_courts) and frontend RPC, so authenticated role must retain EXECUTE.
-- anon must be revoked from both PUBLIC and its direct Supabase grant.
REVOKE EXECUTE ON FUNCTION public.refresh_interval_courts(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refresh_interval_courts(uuid) TO authenticated;

-- set_session_court_bookings: SECURITY DEFINER, admin-only (writes court
-- bookings and refreshes court_cost in the same transaction).
REVOKE EXECUTE ON FUNCTION public.set_session_court_bookings(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_session_court_bookings(uuid, jsonb) TO authenticated;

-- set_session_shuttle_usage: SECURITY DEFINER, admin-only (writes the
-- session's shuttle usage breakdown and recomputes shuttle_fee_total in
-- the same transaction).
REVOKE EXECUTE ON FUNCTION public.set_session_shuttle_usage(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_session_shuttle_usage(uuid, jsonb) TO authenticated;

-- 5. Phase 0 leftovers. These three revokes are in docs/sql-export/09_grants.sql
-- and in Phase 0's migration (2026-09-09-phase0-security.sql), but were never
-- applied to production -- verified still anon=true there on 2026-09-10. This
-- migration carries them so production catches up to the export. Comment and
-- statements copied verbatim from docs/sql-export/09_grants.sql.

-- Soft-delete/gc family: SECURITY INVOKER, no admin guard in the body, and
-- not currently exploitable (RLS still blocks anon's DELETEs on
-- session_payments and session_costs_snapshot) -- but their defence should
-- not rest on RLS alone. Not called from any UI yet.
-- gc_soft_deleted_sessions is driven by pg_cron and needs no role grant.
REVOKE EXECUTE ON FUNCTION public.soft_delete_cancelled_session(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.soft_delete_cancelled_sessions_bulk(uuid[]) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.gc_soft_deleted_sessions(interval) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.soft_delete_cancelled_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.soft_delete_cancelled_sessions_bulk(uuid[]) TO authenticated;

COMMIT;
