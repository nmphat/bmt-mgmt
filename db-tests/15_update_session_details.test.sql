-- update_session_details gộp ba lời gọi rời nhau mà SessionDetailView dùng
-- để lưu một lần sửa buổi (recreate_session_intervals, UPDATE sessions,
-- set_session_court_bookings) vào MỘT transaction. Ba lời gọi rời nhau có
-- hai kiểu hỏng: (1) dời giờ mà không dời sân thì toàn bộ tiền sân về 0 vì
-- refresh_interval_courts chỉ cộng những booking phủ khung giờ HIỆN TẠI;
-- (2) hỏng ở giữa thì điểm danh đã bị xóa còn hai bước sau bị bỏ dở.
BEGIN;

-- Grant-layer: anon không được chạm vào thân hàm.
SELECT login_as('anon');
DO $$
BEGIN
  BEGIN
    PERFORM update_session_details('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'x', 'open'::session_status,
      0, '2026-09-01 11:00:00+00', '2026-09-01 12:00:00+00', '[]'::jsonb);
    RAISE EXCEPTION 'FAIL anon executed update_session_details (REVOKE did not fire)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'ok   anon refused by privilege on update_session_details';
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      RAISE EXCEPTION 'FAIL anon was stopped only by the admin check, not by REVOKE — the grant-level REVOKE on update_session_details is inert';
  END;
END $$;

RESET ROLE;

-- Không phải admin: bị guard trong thân hàm chặn.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
DO $$
BEGIN
  BEGIN
    PERFORM update_session_details('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'x', 'open'::session_status,
      0, '2026-09-01 11:00:00+00', '2026-09-01 12:00:00+00', '[]'::jsonb);
    RAISE EXCEPTION 'FAIL non-admin could update session details';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Chỉ admin%' THEN
      RAISE EXCEPTION 'FAIL non-admin was blocked by the wrong guard: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   non-admin blocked from update_session_details';
  END;
END $$;

-- recreate_session_intervals gọi thẳng: câu lệnh đầu tiên của nó xóa MỌI
-- dòng điểm danh của buổi, nên nó phải có admin check riêng chứ không được
-- dựa vào việc "chỉ update_session_details mới gọi nó".
DO $$
BEGIN
  BEGIN
    PERFORM recreate_session_intervals('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '2026-09-01 20:00:00+00', '2026-09-01 21:00:00+00');
    RAISE EXCEPTION 'FAIL non-admin could rebuild a session''s intervals';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Chỉ admin%' THEN
      RAISE EXCEPTION 'FAIL non-admin was blocked by the wrong guard: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   non-admin blocked from recreate_session_intervals';
  END;
END $$;

SELECT assert_eq(
  (SELECT count(*)::int FROM interval_presence p
    JOIN session_intervals si ON si.id = p.interval_id
    WHERE si.session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  3, 'the refused rebuild destroyed no attendance');

RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

SELECT set_session_court_bookings(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '[{"court_name":"Sân 1","start_time":"2026-09-01T11:00:00+00","end_time":"2026-09-01T12:00:00+00","price_per_hour":120000}]'::jsonb);

SELECT assert_eq(
  (SELECT sum(court_cost) FROM session_intervals
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  120000::numeric, 'starting point: one court hour costs 120000');

SELECT assert_eq(
  (SELECT count(*)::int FROM interval_presence p
    JOIN session_intervals si ON si.id = p.interval_id
    WHERE si.session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  3, 'starting point: three presence rows');

-- ── Sửa mà KHÔNG đổi giờ: không được dựng lại interval ──
-- recreate_session_intervals xóa sạch điểm danh. Admin đổi mỗi cái tiêu đề
-- mà mất hết điểm danh là hỏng.
SELECT update_session_details(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Chỉ đổi tiêu đề', 'open'::session_status, 300000,
  '2026-09-01 11:00:00+00', '2026-09-01 12:00:00+00',
  '[{"court_name":"Sân 1","start_time":"2026-09-01T11:00:00+00","end_time":"2026-09-01T12:00:00+00","price_per_hour":120000}]'::jsonb);

SELECT assert_eq(
  (SELECT count(*)::int FROM interval_presence p
    JOIN session_intervals si ON si.id = p.interval_id
    WHERE si.session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  3, 'a title-only edit keeps every presence row');

SELECT assert_eq(
  (SELECT title FROM sessions WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'Chỉ đổi tiêu đề', 'title was written');

SELECT assert_eq(
  (SELECT court_fee_addon FROM sessions WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  300000::numeric, 'court_fee_addon was written');

-- ── Một payload sân hỏng phải cuộn lại CẢ lần dời giờ ──
-- Đây là kiểu hỏng thứ hai: ba lời gọi rời nhau sẽ commit bước dựng lại
-- interval (điểm danh đã mất) rồi mới chết ở bước ghi sân.
DO $$
BEGIN
  BEGIN
    PERFORM update_session_details(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Tên không được ghi', 'open'::session_status, 0,
      '2026-09-01 20:00:00+00', '2026-09-01 21:00:00+00',
      '[{"court_name":"Sân 1","start_time":"2026-09-01T20:00:00+00","end_time":"2026-09-01T21:00:00+00","price_per_hour":120000},
        {"court_name":"Sân 1","start_time":"2026-09-01T20:30:00+00","end_time":"2026-09-01T21:00:00+00","price_per_hour":120000}]'::jsonb);
    RAISE EXCEPTION 'FAIL an overlapping payload was accepted by update_session_details';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Sân "Sân 1" bị đặt trùng giờ%' THEN
      RAISE EXCEPTION 'FAIL overlapping payload was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   overlapping payload rejected by update_session_details';
  END;
END $$;

SELECT assert_eq(
  (SELECT count(*)::int FROM interval_presence p
    JOIN session_intervals si ON si.id = p.interval_id
    WHERE si.session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  3, 'a rejected save did not destroy attendance');

SELECT assert_eq(
  (SELECT start_time FROM sessions WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  '2026-09-01 11:00:00+00'::timestamptz, 'a rejected save did not move the session');

SELECT assert_eq(
  (SELECT title FROM sessions WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  'Chỉ đổi tiêu đề', 'a rejected save did not write the title');

-- ── Dời giờ VÀ dời sân trong một lời gọi: tiền sân phải sống sót ──
-- Đây là C1. Ba lời gọi rời nhau đưa sum(court_cost) về 0 mà không báo lỗi,
-- vì recreate_session_intervals dời khung giờ còn booking thì ở lại chỗ cũ.
--
-- Lời gọi này CÓ đổi giờ, nên nó chạy xuyên qua recreate_session_intervals
-- lồng bên trong -- và đó là chỗ chứng minh admin check lồng nhau hoạt động:
-- cả hai hàm đều SECURITY DEFINER cùng một owner, auth.uid() đọc GUC
-- request.jwt.claims chứ không đọc current_user, nên hàm trong vẫn thấy đúng
-- người gọi thật. Nếu auth.uid() rỗng ở lời gọi lồng, guard mới sẽ nổ
-- 'Chỉ admin...' ngay đây và cả khối assert bên dưới đỏ.
SELECT update_session_details(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Buổi đã dời giờ', 'open'::session_status, 0,
  '2026-09-01 12:00:00+00', '2026-09-01 13:00:00+00',
  '[{"court_name":"Sân 1","start_time":"2026-09-01T12:00:00+00","end_time":"2026-09-01T13:00:00+00","price_per_hour":120000}]'::jsonb);

SELECT assert_eq(
  (SELECT sum(court_cost) FROM session_intervals
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  120000::numeric, 'court money survives a time edit');

SELECT assert_eq(
  (SELECT count(*)::int FROM session_intervals
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2, 'the moved session still has two intervals');

SELECT assert_eq(
  (SELECT min(start_time) FROM session_intervals
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  '2026-09-01 12:00:00+00'::timestamptz, 'the intervals really did move');

SELECT assert_eq(
  (SELECT start_time FROM sessions WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  '2026-09-01 12:00:00+00'::timestamptz, 'the session row really did move');

-- ── recreate_session_intervals phải tự làm mới tiền sân ──
-- Hàm này dựng lại session_intervals từ đầu (court_cost mặc định 0) và
-- không có trigger nào trên session_intervals đắp lại. `PERFORM
-- refresh_interval_courts` ở cuối thân hàm là thứ duy nhất giữ tiền sân,
-- và không lời gọi nào ở trên khóa được nó: update_session_details ghi sân
-- sau đó, mà set_session_court_bookings tự refresh một lần nữa.
SELECT recreate_session_intervals(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '2026-09-01 12:00:00+00', '2026-09-01 13:00:00+00');

SELECT assert_eq(
  (SELECT sum(court_cost) FROM session_intervals
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  120000::numeric, 'recreate_session_intervals refreshes court_cost itself');

SELECT assert_eq(
  (SELECT sum(active_court_count)::int FROM session_intervals
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2, 'recreate_session_intervals refreshes active_court_count itself');

-- ── p_court_fee_addon = NULL phải quy về 0, không được ném 23502 ──
-- court_fee_addon là NOT NULL DEFAULT 0. SessionDetailView bind nó bằng
-- v-model.number trên input type="number", nên xóa trắng ô đó gửi lên NULL,
-- và saveSession in nguyên văn error.message: người dùng nhận một chuỗi
-- 23502 tiếng Anh. create_session_with_bookings đã COALESCE từ vòng trước;
-- đường SỬA thì chưa.
SELECT update_session_details(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Tiêu đề NULL addon', 'open'::session_status,
  NULL, '2026-09-01 12:00:00+00', '2026-09-01 13:00:00+00',
  '[{"court_name":"Sân 1","start_time":"2026-09-01T12:00:00+00","end_time":"2026-09-01T13:00:00+00","price_per_hour":120000}]'::jsonb);

SELECT assert_eq(
  (SELECT court_fee_addon FROM sessions WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::numeric, 'update: a NULL court_fee_addon is coalesced to 0, not rejected by the column');

RESET ROLE;
ROLLBACK;
