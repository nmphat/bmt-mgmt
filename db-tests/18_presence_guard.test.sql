-- Hai nửa của cùng một lỗi: người CHƯA đăng ký buổi mà có dòng
-- interval_presence.
--   - Nửa MÁY TÍNH TIỀN: calculate_session_costs đếm mẫu số từ
--     interval_presence nhưng lấy tử số từ session_registrations, nên dòng
--     điểm danh đó chia nhỏ tiền thêm một suất rồi vứt suất đó đi. Không
--     lỗi, không cảnh báo. Đo trên production: một buổi có 3 dòng như vậy,
--     view báo 240000 còn máy tính tiền chỉ thu 180000.
--   - Nửa CHẶN GHI: trigger BEFORE INSERT OR UPDATE trên interval_presence,
--     cùng hình dạng với check_charge_member_registered.
-- Hai nửa phải được pin RIÊNG: production đã có sẵn dòng kiểu này từ trước
-- khi có trigger, nên nửa máy tính tiền phải tự đứng được.
BEGIN;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- ── Nửa máy tính tiền ──
-- Admin (1111…) KHÔNG đăng ký buổi fixture. Tắt trigger đúng một lệnh INSERT
-- để dựng lại đúng hình dạng dữ liệu production đang mang.
ALTER TABLE interval_presence DISABLE TRIGGER check_presence_member_registered;
INSERT INTO interval_presence (interval_id, member_id, is_present)
VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', '11111111-1111-1111-1111-111111111111', true);
ALTER TABLE interval_presence ENABLE TRIGGER check_presence_member_registered;

SELECT assert_eq(
  (SELECT count(*)::int FROM interval_presence p
    WHERE p.member_id = '11111111-1111-1111-1111-111111111111'),
  1, 'the unregistered presence row really is there');

-- Đúng con số của 00_smoke: A = 280000, B = 140000. Dòng điểm danh của
-- người chưa đăng ký không được làm suy chuyển một đồng nào.
-- Nếu mẫu số vẫn đếm cả dòng đó: interval 1 có real_present_count = 3 thay
-- vì 2, và A tụt xuống 234000 còn B tụt xuống 94000 -- 92000đ bốc hơi.
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  280000::numeric, 'member A is unaffected by an unregistered presence row');

SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  140000::numeric, 'member B is unaffected by an unregistered presence row');

-- Người chưa đăng ký vẫn không xuất hiện trong hóa đơn (tử số không đổi).
SELECT assert_eq(
  (SELECT count(*)::int FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  2, 'the unregistered member still gets no bill');

DELETE FROM interval_presence WHERE member_id = '11111111-1111-1111-1111-111111111111';

-- ── Nửa chặn ghi ──
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

DO $$
BEGIN
  BEGIN
    INSERT INTO interval_presence (interval_id, member_id, is_present)
    VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', '11111111-1111-1111-1111-111111111111', true);
    RAISE EXCEPTION 'FAIL presence for an unregistered member was written';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Thành viên này chưa đăng ký buổi%' THEN
      RAISE EXCEPTION 'FAIL unregistered presence was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   presence for an unregistered member rejected';
  END;
END $$;

-- UPDATE cũng phải chặn: dời một dòng điểm danh hợp lệ sang người chưa đăng
-- ký làm tiền biến mất y hệt.
DO $$
BEGIN
  BEGIN
    UPDATE interval_presence
    SET member_id = '11111111-1111-1111-1111-111111111111'
    WHERE interval_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1'
      AND member_id = '22222222-2222-2222-2222-222222222222';
    RAISE EXCEPTION 'FAIL a presence row was moved onto an unregistered member';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Thành viên này chưa đăng ký buổi%' THEN
      RAISE EXCEPTION 'FAIL the UPDATE was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   moving a presence row onto an unregistered member rejected';
  END;
END $$;

-- Điểm danh BÌNH THƯỜNG của người đã đăng ký vẫn phải chạy: trigger không
-- được chặn nhầm đường ghi thật (SessionDetailView upsert thẳng vào bảng).
UPDATE interval_presence SET is_present = false
WHERE interval_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'
  AND member_id = '22222222-2222-2222-2222-222222222222';

SELECT assert_eq(
  (SELECT is_present FROM interval_presence
    WHERE interval_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'
      AND member_id = '22222222-2222-2222-2222-222222222222'),
  false, 'a registered member can still be marked absent');

-- Hai hàm thêm người vào buổi ghi registration TRƯỚC rồi mới ghi presence,
-- nên trigger không kẹt chúng. Nếu ai đảo thứ tự đó, hai assert dưới đây đỏ.
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

SELECT add_member_to_session_full_presence(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111');

SELECT assert_eq(
  (SELECT count(*)::int FROM interval_presence
    WHERE member_id = '11111111-1111-1111-1111-111111111111'),
  2, 'add_member_to_session_full_presence still registers before it marks presence');

SELECT remove_member_from_session(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111');

SELECT batch_add_members_to_session(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', ARRAY['11111111-1111-1111-1111-111111111111'::uuid]);

SELECT assert_eq(
  (SELECT count(*)::int FROM interval_presence
    WHERE member_id = '11111111-1111-1111-1111-111111111111'),
  2, 'batch_add_members_to_session still registers before it marks presence');

RESET ROLE;
ROLLBACK;
