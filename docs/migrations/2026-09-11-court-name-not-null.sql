-- session_court_bookings.court_name: close the reachable-NULL/blank hole.
-- Run once, after 2026-09-09-phase1-pricing.sql.
--
-- Reviewed against docs/sql-export/{02_tables,03_constraints,06_functions}.sql
-- as of commit 822e8c2. Production measurement, 2026-09-11: 47 booking
-- rows, 0 with a NULL court_name, 0 matching '^\s*$', 0 with leading or
-- trailing whitespace, only 2 distinct court names -- both the NOT NULL
-- column change and the CHECK constraint apply cleanly. The function body
-- below is copied verbatim from 06_functions.sql after adding the input
-- guard; no other function is touched.
--
-- Two layers, deliberately: the CHECK constraint is the backstop that
-- catches every writer (including create_session_with_bookings, whose
-- COALESCE(..., 'Sân 1') only falls through on NULL, never on '' --
-- it can still insert a blank name today, before and after this
-- migration); the RPC guard is what turns a bad admin-UI call into a
-- clear Vietnamese error message instead of a raw 23514 violation.
--
-- Pre-flight (run first, expect 0 for both):
--   SELECT count(*) FROM session_court_bookings
--   WHERE court_name IS NULL OR court_name ~ '^\s*$';
--   SELECT count(*) FROM session_court_bookings
--   WHERE court_name ~ '^\s' OR court_name ~ '\s$';

BEGIN;

-- ALTER COLUMN ... SET NOT NULL and ADD CONSTRAINT both take ACCESS
-- EXCLUSIVE on session_court_bookings and hold it to COMMIT, same reason
-- as the phase 1 migration's lock_timeout. Run in a quiet window
-- regardless.
SET LOCAL lock_timeout = '5s';

-- SET NOT NULL on a column that is already NOT NULL is a no-op, so this
-- statement alone makes the script safe to run twice -- no DO $$ IF NOT
-- EXISTS guard needed.
ALTER TABLE public.session_court_bookings ALTER COLUMN court_name SET NOT NULL;

-- ADD CONSTRAINT is not idempotent on its own (a second run would error
-- "constraint already exists"), so guard it the same way the phase 1
-- migration guards session_court_bookings_time_order_check -- matching
-- conrelid too, so a same-named constraint on some other table can't
-- fool the check.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'session_court_bookings_court_name_not_blank'
      AND conrelid = 'public.session_court_bookings'::regclass
  ) THEN
    ALTER TABLE public.session_court_bookings
      ADD CONSTRAINT session_court_bookings_court_name_not_blank CHECK (court_name ~ '\S');
  END IF;
END $$;

-- Function body copied verbatim from docs/sql-export/06_functions.sql (this
-- change). No REVOKE/GRANT here: CREATE OR REPLACE FUNCTION preserves the
-- function's existing ACL, and docs/sql-export/09_grants.sql already
-- carries this function's REVOKE EXECUTE ... FROM PUBLIC, anon and
-- GRANT ... TO authenticated, both already applied to production. Do not
-- DROP FUNCTION + CREATE here -- that would reset to Supabase's default
-- privileges and hand anon back its EXECUTE.
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

    -- Một sân không tên là vô nghĩa. Thiếu key, JSON null, hoặc chỉ có
    -- khoảng trắng (kể cả tab, xuống dòng -- trim() một tham số chỉ cắt
    -- ký tự space 0x20, không cắt các khoảng trắng khác) đều phải bị chặn
    -- ở đây, trước khi ghi -- không lặng lẽ mặc định về 'Sân 1' như
    -- create_session_with_bookings vẫn làm. IS NULL vẫn cần giữ riêng vì
    -- '~' so với NULL cho ra NULL chứ không phải true, nên regex một mình
    -- sẽ để lọt key bị thiếu.
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_bookings) e
        WHERE e->>'court_name' IS NULL OR e->>'court_name' ~ '^\s*$'
    ) THEN
        RAISE EXCEPTION 'Thiếu tên sân (court_name) trong dữ liệu đặt sân';
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

COMMIT;
