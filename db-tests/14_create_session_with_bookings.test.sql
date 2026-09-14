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

-- Tên sân rỗng / chỉ có khoảng trắng / thiếu hẳn key. COALESCE chỉ rơi khi
-- NULL nên ba hình dạng này trước đây lọt qua và đập vào CHECK
-- court_name ~ '\S': người dùng nhận nguyên văn một chuỗi 23514 tiếng Anh.
-- Luật phải giống hệt set_session_court_bookings -- từ chối, không lặng lẽ
-- mặc định về 'Sân 1'.
DO $$
DECLARE
  v_payload jsonb;
BEGIN
  FOREACH v_payload IN ARRAY ARRAY[
    '[{"court_name":"","start_time":"2026-09-02T11:00:00+00","end_time":"2026-09-02T12:00:00+00","price_per_hour":120000}]'::jsonb,
    '[{"court_name":" \t ","start_time":"2026-09-02T11:00:00+00","end_time":"2026-09-02T12:00:00+00","price_per_hour":120000}]'::jsonb,
    '[{"start_time":"2026-09-02T11:00:00+00","end_time":"2026-09-02T12:00:00+00","price_per_hour":120000}]'::jsonb
  ]
  LOOP
    BEGIN
      PERFORM create_session_with_bookings(
        'Buổi sân không tên', '2026-09-02 11:00:00+00', '2026-09-02 12:00:00+00',
        0, 0, '11111111-1111-1111-1111-111111111111', v_payload, 0);
      RAISE EXCEPTION 'FAIL a blank court_name was accepted by create_session_with_bookings (payload %)', v_payload;
    EXCEPTION
      WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
        IF SQLERRM NOT LIKE 'Thiếu tên sân%' THEN
          RAISE EXCEPTION 'FAIL blank court_name was rejected for the wrong reason (%): %', v_payload, SQLERRM;
        END IF;
        RAISE NOTICE 'ok   create: blank court_name rejected in Vietnamese';
      WHEN OTHERS THEN
        RAISE EXCEPTION 'FAIL blank court_name reached the CHECK constraint (%) instead of the RPC guard', SQLERRM;
    END;
  END LOOP;
END $$;

SELECT assert_eq(
  (SELECT count(*)::int FROM sessions WHERE title = 'Buổi sân không tên'),
  0, 'create: a blank court name leaves no half-created session behind');

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

  -- Giá từng sân phải được ghi đúng như client gửi. Đây là đường tạo buổi
  -- duy nhất: nếu nó vứt p_bookings[].price_per_hour đi thì MỌI buổi mới
  -- đều được tạo miễn phí và không có gì báo.
  PERFORM assert_eq(
    (SELECT price_per_hour FROM session_court_bookings
      WHERE session_id = v_sid AND court_name = 'Sân 1'),
    120000::numeric, 'create: the submitted price_per_hour is stored, not discarded');

  PERFORM assert_eq(
    (SELECT price_per_hour FROM session_court_bookings
      WHERE session_id = v_sid AND court_name = 'Sân 2'),
    100000::numeric, 'create: each booking keeps its own price');

  -- Và phải chảy tiếp vào tiền sân của từng interval: 4 interval 30 phút,
  -- mỗi interval (120000 + 100000)/2 = 110000 -> tổng 220000.
  PERFORM assert_eq(
    (SELECT sum(court_cost) FROM session_intervals WHERE session_id = v_sid),
    220000::numeric, 'create: prices reach session_intervals.court_cost');

  PERFORM assert_eq(
    (SELECT count(*)::int FROM session_intervals WHERE session_id = v_sid),
    2, 'create: a one-hour session gets two 30-minute intervals');
END $$;

-- Ba cột tiền của sessions phải là NOT NULL. price_per_hour = NULL làm
-- (v_price_per_hour / 2.0) * active_court_count ra NULL, NULL lan qua tổng,
-- và cả buổi thành miễn phí trên nhánh giá cũ mà không có gì báo.
-- Production: 0/54 buổi có NULL ở bất kỳ cột nào trong ba cột.
DO $$
DECLARE
  c text;
BEGIN
  FOREACH c IN ARRAY ARRAY['price_per_hour','court_fee_addon','shuttle_fee_total']
  LOOP
    BEGIN
      EXECUTE format(
        'INSERT INTO sessions (title, start_time, end_time, %I) VALUES (%L, %L, %L, NULL)',
        c, 'Buổi NULL tiền', '2026-09-04 11:00:00+00', '2026-09-04 12:00:00+00');
      RAISE EXCEPTION 'FAIL sessions.% accepted NULL', c;
    EXCEPTION
      WHEN not_null_violation THEN
        RAISE NOTICE 'ok   sessions.% refused NULL by the column NOT NULL (23502)', c;
      WHEN OTHERS THEN
        IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
        RAISE EXCEPTION 'FAIL sessions.% refused NULL for the wrong reason: %', c, SQLERRM;
    END;
  END LOOP;
END $$;

-- create_session_with_bookings truyền thẳng ba tham số đó vào cột, nên một
-- client gửi NULL sẽ chết ở cột và người dùng nhận nguyên văn 23502 tiếng
-- Anh. RPC quy về 0 -- đúng bằng DEFAULT mà cột đã khai báo.
DO $$
DECLARE v_sid uuid;
BEGIN
  v_sid := create_session_with_bookings(
    'Buổi tiền NULL', '2026-09-04 11:00:00+00', '2026-09-04 12:00:00+00',
    NULL, NULL, '11111111-1111-1111-1111-111111111111',
    '[{"court_name":"Sân 1","start_time":"2026-09-04T11:00:00+00","end_time":"2026-09-04T12:00:00+00","price_per_hour":120000}]'::jsonb,
    NULL);

  PERFORM assert_eq(
    (SELECT price_per_hour || '/' || court_fee_addon || '/' || shuttle_fee_total
       FROM sessions WHERE id = v_sid),
    '0/0/0', 'create: NULL money parameters are coalesced to 0, not rejected by the column');
END $$;

-- court_name NOT NULL phải tự đứng được. CHECK constraint không thay thế
-- được nó: 'court_name ~ \S' cho ra NULL khi court_name là NULL, và một
-- CHECK trả NULL thì ĐẠT. Bỏ NOT NULL đi là mở lại đường ghi booking không
-- tên sân mà không có gì chặn.
DO $$
BEGIN
  BEGIN
    INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time, price_per_hour)
    VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', NULL,
            '2026-09-01T11:00:00+00', '2026-09-01T11:30:00+00', 100000);
    RAISE EXCEPTION 'FAIL a booking with court_name = NULL was written';
  EXCEPTION
    WHEN not_null_violation THEN
      RAISE NOTICE 'ok   court_name = NULL refused by the column NOT NULL (23502)';
    WHEN OTHERS THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      RAISE EXCEPTION 'FAIL court_name = NULL was refused for the wrong reason (%), not the NOT NULL constraint', SQLERRM;
  END;
END $$;


-- ── Khung sân phải nằm TRONG giờ của buổi, ở cả đường TẠO buổi ──
-- Buổi tạo được thì phải sửa lại được: set_session_court_bookings từ chối
-- hình dạng này, nên create_session_with_bookings cũng phải từ chối, nếu
-- không màn hình sửa buổi sẽ không lưu lại được chính buổi vừa tạo.
DO $$
DECLARE
  v_payloads text[] := ARRAY[
    '[{"court_name":"Sân 1","start_time":"2026-09-06T10:00:00+00","end_time":"2026-09-06T12:00:00+00","price_per_hour":120000}]',
    '[{"court_name":"Sân 2","start_time":"2026-09-06T11:00:00+00","end_time":"2026-09-06T14:00:00+00","price_per_hour":120000}]',
    '[{"court_name":"Sân 3","start_time":"2026-09-07T11:00:00+00","end_time":"2026-09-07T12:00:00+00","price_per_hour":120000}]'
  ];
  v_p text;
  v_before int;
BEGIN
  SELECT count(*) INTO v_before FROM sessions;

  FOREACH v_p IN ARRAY v_payloads LOOP
    BEGIN
      PERFORM create_session_with_bookings(
        'Buổi sân lệch giờ', '2026-09-06 11:00:00+00', '2026-09-06 12:00:00+00',
        0, 0, '11111111-1111-1111-1111-111111111111', v_p::jsonb, 0);
      RAISE EXCEPTION 'FAIL a session was created with a booking outside its window: %', v_p;
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      IF SQLERRM NOT LIKE 'Khung giờ của sân%' THEN
        RAISE EXCEPTION 'FAIL out-of-window booking refused for the wrong reason: % (%)', SQLERRM, v_p;
      END IF;
      RAISE NOTICE 'ok   create: out-of-window booking refused in Vietnamese';
    END;
  END LOOP;

  -- Guard phải chạy TRƯỚC mọi INSERT: không được để lại buổi tạo dở.
  PERFORM assert_eq((SELECT count(*)::int FROM sessions), v_before,
    'create: a refused out-of-window payload left no half-created session');
END $$;

-- Khít hai đầu vẫn tạo được.
DO $$
DECLARE v_sid uuid;
BEGIN
  v_sid := create_session_with_bookings(
    'Buổi sân khít giờ', '2026-09-06 11:00:00+00', '2026-09-06 12:00:00+00',
    0, 0, '11111111-1111-1111-1111-111111111111',
    '[{"court_name":"Sân 1","start_time":"2026-09-06T11:00:00+00","end_time":"2026-09-06T12:00:00+00","price_per_hour":120000}]'::jsonb,
    0);

  PERFORM assert_eq(
    (SELECT sum(court_cost) FROM session_intervals WHERE session_id = v_sid),
    120000::numeric, 'create: a booking flush with both ends of the session is still legal');
END $$;


ROLLBACK;
