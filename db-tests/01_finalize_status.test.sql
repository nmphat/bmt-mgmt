BEGIN;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- Finalize once, then let member A pay in full.
SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

UPDATE session_costs_snapshot
SET paid_amount = final_amount, status = 'paid'
WHERE member_id = '22222222-2222-2222-2222-222222222222';

SELECT assert_eq(
  (SELECT status::text FROM session_costs_snapshot
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  'paid', 'A is paid before the price change');

-- Admin raises the shuttle fee and re-finalizes.
UPDATE sessions SET shuttle_fee_total = 240000
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- A now owes more than they paid, so the row must drop back to partial.
SELECT assert_eq(
  (SELECT status::text FROM session_costs_snapshot
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  'partial', 'A falls back to partial after the price rise');

-- And the debt must be visible again.
SELECT assert_eq(
  (SELECT count(*)::int FROM view_member_debt_summary
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  1, 'A reappears in the debt summary');

-- B never paid, so B stays pending.
SELECT assert_eq(
  (SELECT status::text FROM session_costs_snapshot
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  'pending', 'B stays pending');

-- ── Buổi tạo bằng đúng giá trị mặc định của form: không được chốt im lặng ──
-- CreateSessionView gửi p_price_per_hour = 0, mọi booking price_per_hour = 0
-- và court_fee_addon = 0. Trước đây finalize_session bỏ qua mọi thành viên có
-- final_total = 0, nên buổi chuyển sang 'waiting_for_payment' với ĐÚNG 0 dòng
-- snapshot: đã chốt, không ai nợ, không QR nào, không lỗi nào.
DO $$
DECLARE
  v_sid uuid;
BEGIN
  v_sid := create_session_with_bookings(
    'Buổi mặc định', '2026-09-03 11:00:00+00', '2026-09-03 12:00:00+00',
    0, 0, '11111111-1111-1111-1111-111111111111',
    '[{"court_name":"Sân 1","start_time":"2026-09-03T11:00:00+00","end_time":"2026-09-03T12:00:00+00","price_per_hour":0}]'::jsonb,
    0);

  INSERT INTO session_registrations (session_id, member_id) VALUES
    (v_sid, '22222222-2222-2222-2222-222222222222'),
    (v_sid, '33333333-3333-3333-3333-333333333333');

  INSERT INTO interval_presence (interval_id, member_id, is_present)
  SELECT si.id, r.member_id, true
  FROM session_intervals si
  JOIN session_registrations r ON r.session_id = si.session_id
  WHERE si.session_id = v_sid;

  -- Engine xác nhận hình dạng: mọi người đều 0 đồng.
  PERFORM assert_eq(
    (SELECT count(*)::int FROM calculate_session_costs(v_sid) WHERE final_total > 0),
    0, 'default-shaped session really does charge nobody anything');

  BEGIN
    PERFORM finalize_session(v_sid);
    RAISE EXCEPTION 'FAIL a zero-cost session finalized silently';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Buổi này không có khoản nào để chia%' THEN
      RAISE EXCEPTION 'FAIL zero-cost finalize was refused for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   zero-cost finalize refused in Vietnamese';
  END;

  PERFORM assert_eq(
    (SELECT count(*)::int FROM session_costs_snapshot WHERE session_id = v_sid),
    0, 'refused finalize wrote no snapshot rows');

  -- Đây là nửa quan trọng: UPDATE trạng thái chạy TRƯỚC vòng lặp, nên chỉ
  -- riêng việc RAISE cuộn nó lại mới giữ được buổi ở 'open'. (Không thể dời
  -- UPDATE xuống sau vòng lặp: trigger check_session_completion dựa vào việc
  -- buổi đã ở 'waiting_for_payment' khi các dòng snapshot chuyển sang 'paid'.)
  PERFORM assert_eq(
    (SELECT status::text FROM sessions WHERE id = v_sid),
    'open', 'refused finalize left the session status untouched');

  -- Nhập tiền vào rồi thì chốt được bình thường -- guard không được chặn
  -- một buổi có tiền thật.
  UPDATE sessions SET court_fee_addon = 200000 WHERE id = v_sid;
  PERFORM finalize_session(v_sid);

  PERFORM assert_eq(
    (SELECT count(*)::int FROM session_costs_snapshot WHERE session_id = v_sid),
    2, 'the same session finalizes once it has money to split');

  PERFORM assert_eq(
    (SELECT status::text FROM sessions WHERE id = v_sid),
    'waiting_for_payment', 'a session with money to split still reaches waiting_for_payment');
END $$;

ROLLBACK;
