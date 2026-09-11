BEGIN;

-- Anon must never reach the function body at all: the grant-layer REVOKE
-- should refuse the call outright (insufficient_privilege). This proves
-- 09_grants.sql's REVOKE EXECUTE ... FROM PUBLIC, anon is effective and
-- not just present -- if either of anon's two grant paths (PostgreSQL's
-- default PUBLIC grant, Supabase's own default-privileges grant direct to
-- anon) survived, this call would instead fall through into the body and
-- trip the admin check (raise_exception), not the grant system.
SELECT login_as('anon');

DO $$
BEGIN
  BEGIN
    PERFORM set_session_court_bookings('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '[]'::jsonb);
    RAISE EXCEPTION 'FAIL anon executed set_session_court_bookings (REVOKE did not fire)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'ok   anon refused by privilege on set_session_court_bookings';
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      RAISE EXCEPTION 'FAIL anon was stopped only by the admin check, not by REVOKE — the grant-level REVOKE on set_session_court_bookings is inert';
  END;
END $$;

RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

SELECT set_session_court_bookings(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '[{"court_name":"Sân 1","start_time":"2026-09-01T11:00:00+00","end_time":"2026-09-01T11:30:00+00","price_per_hour":120000},
    {"court_name":"Sân 1","start_time":"2026-09-01T11:30:00+00","end_time":"2026-09-01T12:00:00+00","price_per_hour":130000}]'::jsonb);

SELECT assert_eq(
  (SELECT count(*)::int FROM session_court_bookings
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2, 'two bookings written');

-- RPC phải tự gọi refresh_interval_courts; caller không phải nhớ.
SELECT assert_eq(
  (SELECT court_cost FROM session_intervals WHERE idx = 0
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  60000::numeric, 'intervals refreshed by the RPC itself');

-- Gọi lại phải thay thế, không cộng dồn.
SELECT set_session_court_bookings(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '[{"court_name":"Sân 2","start_time":"2026-09-01T11:00:00+00","end_time":"2026-09-01T12:00:00+00","price_per_hour":100000}]'::jsonb);

SELECT assert_eq(
  (SELECT count(*)::int FROM session_court_bookings
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1, 'second call replaces rather than appends');

-- Booking có end_time đi trước start_time: CHECK constraint phải từ
-- chối, đúng SQLSTATE 23514 (check_violation) -- không phải một lý do
-- khác (vd. một lỗi kiểu dữ liệu hay quyền hạn) trùng hợp cũng chặn được.
DO $$
BEGIN
  BEGIN
    PERFORM set_session_court_bookings(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '[{"court_name":"Sân lỗi","start_time":"2026-09-01T11:10:00+00","end_time":"2026-09-01T11:05:00+00","price_per_hour":120000}]'::jsonb);
    RAISE EXCEPTION 'FAIL inverted booking (end before start) was written';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'ok   inverted booking refused by the CHECK constraint (23514)';
    WHEN OTHERS THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      RAISE EXCEPTION 'FAIL inverted booking was refused for the wrong reason (%), not the CHECK constraint', SQLERRM;
  END;
END $$;

-- Booking có độ dài bằng 0 (end_time = start_time) cũng phải bị từ chối
-- -- đây là lý do constraint dùng '>' chứ không phải '>='.
DO $$
BEGIN
  BEGIN
    PERFORM set_session_court_bookings(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '[{"court_name":"Sân lỗi","start_time":"2026-09-01T11:10:00+00","end_time":"2026-09-01T11:10:00+00","price_per_hour":120000}]'::jsonb);
    RAISE EXCEPTION 'FAIL zero-length booking (end = start) was written';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'ok   zero-length booking refused by the CHECK constraint (23514)';
    WHEN OTHERS THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      RAISE EXCEPTION 'FAIL zero-length booking was refused for the wrong reason (%), not the CHECK constraint', SQLERRM;
  END;
END $$;

-- Cả hai lần ghi hỏng ở trên đều bị từ chối bởi INSERT, nhưng hàm xóa
-- (DELETE) trước rồi mới ghi (INSERT) -- nếu INSERT thất bại mà DELETE
-- không được cuộn lại theo, booking "Sân 2" của lần gọi thành công trước
-- đó sẽ biến mất mà không có gì thay thế. Phải còn nguyên y hệt.
SELECT assert_eq(
  (SELECT count(*)::int FROM session_court_bookings
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1, 'rejected write left booking count untouched');

SELECT assert_eq(
  (SELECT court_name FROM session_court_bookings
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'Sân 2', 'rejected write did not delete the pre-existing booking');

SELECT assert_eq(
  (SELECT court_cost FROM session_intervals WHERE idx = 0
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  50000::numeric, 'rejected write left interval 0 court_cost untouched');

SELECT assert_eq(
  (SELECT court_cost FROM session_intervals WHERE idx = 1
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  50000::numeric, 'rejected write left interval 1 court_cost untouched');

SELECT assert_eq(
  (SELECT active_court_count FROM session_intervals WHERE idx = 0
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1, 'rejected write left interval 0 active_court_count untouched');

-- court_name thiếu, JSON null, hoặc chỉ có khoảng trắng: một sân không tên
-- là vô nghĩa, không được lặng lẽ ghi. Guard phải chặn cả ba trước khi
-- xóa/ghi bất cứ gì.

-- Thiếu key "court_name".
DO $$
BEGIN
  BEGIN
    PERFORM set_session_court_bookings(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '[{"start_time":"2026-09-01T11:00:00+00","end_time":"2026-09-01T11:30:00+00","price_per_hour":120000}]'::jsonb);
    RAISE EXCEPTION 'FAIL booking missing "court_name" was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Thiếu tên sân (court_name)%' THEN
      RAISE EXCEPTION 'FAIL missing "court_name" was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   missing "court_name" rejected';
  END;
END $$;

-- court_name là JSON null.
DO $$
BEGIN
  BEGIN
    PERFORM set_session_court_bookings(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '[{"court_name":null,"start_time":"2026-09-01T11:00:00+00","end_time":"2026-09-01T11:30:00+00","price_per_hour":120000}]'::jsonb);
    RAISE EXCEPTION 'FAIL booking with court_name = null was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Thiếu tên sân (court_name)%' THEN
      RAISE EXCEPTION 'FAIL court_name = null was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   court_name = null rejected';
  END;
END $$;

-- court_name chỉ có khoảng trắng.
DO $$
BEGIN
  BEGIN
    PERFORM set_session_court_bookings(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '[{"court_name":"   ","start_time":"2026-09-01T11:00:00+00","end_time":"2026-09-01T11:30:00+00","price_per_hour":120000}]'::jsonb);
    RAISE EXCEPTION 'FAIL booking with blank court_name was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Thiếu tên sân (court_name)%' THEN
      RAISE EXCEPTION 'FAIL blank court_name was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   blank court_name rejected';
  END;
END $$;

-- Guard chạy trước DELETE, nên ba lần ghi hỏng ở trên không được đụng vào
-- booking "Sân 2" hay các interval của nó -- phải còn nguyên y hệt.
SELECT assert_eq(
  (SELECT count(*)::int FROM session_court_bookings
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1, 'rejected court_name writes left booking count untouched');

SELECT assert_eq(
  (SELECT court_name FROM session_court_bookings
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'Sân 2', 'rejected court_name writes did not delete the pre-existing booking');

SELECT assert_eq(
  (SELECT court_cost FROM session_intervals WHERE idx = 0
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  50000::numeric, 'rejected court_name writes left interval 0 court_cost untouched');

SELECT assert_eq(
  (SELECT court_cost FROM session_intervals WHERE idx = 1
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  50000::numeric, 'rejected court_name writes left interval 1 court_cost untouched');

-- Payload hợp lệ vẫn ghi được bình thường -- guard mới không được
-- false-positive trên dữ liệu tốt.
SELECT set_session_court_bookings(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '[{"court_name":"Sân 3","start_time":"2026-09-01T11:00:00+00","end_time":"2026-09-01T12:00:00+00","price_per_hour":110000}]'::jsonb);

SELECT assert_eq(
  (SELECT court_name FROM session_court_bookings
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'Sân 3', 'a valid court_name still writes after the new guard');

RESET ROLE;

-- Không phải admin: bị từ chối.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

DO $$
BEGIN
  BEGIN
    PERFORM set_session_court_bookings('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '[]'::jsonb);
    RAISE EXCEPTION 'FAIL non-admin could write court bookings';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    -- Session is still 'open' here, so the admin guard is the only thing
    -- that can legitimately stop this call. Pin the message so a guard
    -- that fires for some other reason cannot pass this test.
    IF SQLERRM NOT LIKE 'Chỉ admin%' THEN
      RAISE EXCEPTION 'FAIL non-admin was blocked by the wrong guard: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   non-admin blocked';
  END;
END $$;

RESET ROLE;

-- Buổi đã chốt: bị từ chối, kể cả admin.
UPDATE sessions SET status = 'waiting_for_payment'
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

DO $$
BEGIN
  BEGIN
    PERFORM set_session_court_bookings('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '[]'::jsonb);
    RAISE EXCEPTION 'FAIL admin could edit a finalized session';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    -- Caller is admin, so only the status check can legitimately stop
    -- this call. Reject a false pass through the admin guard itself.
    IF SQLERRM LIKE 'Chỉ admin%' THEN
      RAISE EXCEPTION 'FAIL admin was blocked by the admin guard instead of the status check: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   finalized session is locked';
  END;
END $$;

RESET ROLE;
ROLLBACK;
