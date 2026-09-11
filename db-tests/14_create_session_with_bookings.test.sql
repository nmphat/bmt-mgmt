-- create_session_with_bookings là đường tạo buổi DUY NHẤT của ứng dụng
-- (bản 7 tham số đã bị bỏ ở nhánh này) và trước file này nó không có một
-- test nào -- chỉ được nhắc tới trong một comment. Lỗi của nó được
-- CreateSessionView hiển thị nguyên văn cho người dùng, nên nó phải nói
-- tiếng Việt chứ không để CHECK constraint ném 23514 tiếng Anh.
BEGIN;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- Booking đảo giờ: guard chặn bằng tiếng Việt, không phải CHECK constraint.
DO $$
BEGIN
  BEGIN
    PERFORM create_session_with_bookings(
      'Buổi giờ đảo', '2026-09-02 11:00:00+00', '2026-09-02 12:00:00+00',
      0, 0, '11111111-1111-1111-1111-111111111111',
      '[{"court_name":"Sân 1","start_time":"2026-09-02T12:00:00+00","end_time":"2026-09-02T11:00:00+00","price_per_hour":120000}]'::jsonb,
      0);
    RAISE EXCEPTION 'FAIL inverted booking was accepted by create_session_with_bookings';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      IF SQLERRM NOT LIKE 'Giờ kết thúc phải sau giờ bắt đầu%' THEN
        RAISE EXCEPTION 'FAIL inverted booking was rejected for the wrong reason: %', SQLERRM;
      END IF;
      RAISE NOTICE 'ok   create: inverted booking rejected in Vietnamese';
    WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL inverted booking reached the CHECK constraint (%) instead of the RPC guard', SQLERRM;
  END;
END $$;

-- Guard phải chạy TRƯỚC khi ghi: không được để lại một buổi mồ côi không
-- có sân nào.
SELECT assert_eq(
  (SELECT count(*)::int FROM sessions WHERE title = 'Buổi giờ đảo'),
  0, 'create: a rejected payload leaves no half-created session behind');

-- Hai khung chồng giờ trên cùng một sân: một giờ sân 120000 sẽ bị tính
-- thành 240000 nếu lọt.
DO $$
BEGIN
  BEGIN
    PERFORM create_session_with_bookings(
      'Buổi trùng sân', '2026-09-02 11:00:00+00', '2026-09-02 12:00:00+00',
      0, 0, '11111111-1111-1111-1111-111111111111',
      '[{"court_name":"Sân 1","start_time":"2026-09-02T11:00:00+00","end_time":"2026-09-02T12:00:00+00","price_per_hour":120000},
        {"court_name":"Sân 1","start_time":"2026-09-02T11:00:00+00","end_time":"2026-09-02T12:00:00+00","price_per_hour":120000}]'::jsonb,
      0);
    RAISE EXCEPTION 'FAIL overlapping bookings were accepted by create_session_with_bookings';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Sân "Sân 1" bị đặt trùng giờ%' THEN
      RAISE EXCEPTION 'FAIL overlapping bookings were rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   create: overlapping bookings rejected, naming the court';
  END;
END $$;

SELECT assert_eq(
  (SELECT count(*)::int FROM sessions WHERE title = 'Buổi trùng sân'),
  0, 'create: a rejected overlap leaves no half-created session behind');

-- Payload hợp lệ vẫn tạo được buổi, và hai sân khác nhau cùng giờ không
-- phải là trùng.
DO $$
DECLARE v_sid uuid;
BEGIN
  v_sid := create_session_with_bookings(
    'Buổi hợp lệ', '2026-09-02 11:00:00+00', '2026-09-02 12:00:00+00',
    0, 0, '11111111-1111-1111-1111-111111111111',
    '[{"court_name":"Sân 1","start_time":"2026-09-02T11:00:00+00","end_time":"2026-09-02T12:00:00+00","price_per_hour":120000},
      {"court_name":"Sân 2","start_time":"2026-09-02T11:00:00+00","end_time":"2026-09-02T12:00:00+00","price_per_hour":100000}]'::jsonb,
    0);

  PERFORM assert_eq(
    (SELECT count(*)::int FROM session_court_bookings WHERE session_id = v_sid),
    2, 'create: two courts at the same time are written');
END $$;

ROLLBACK;
