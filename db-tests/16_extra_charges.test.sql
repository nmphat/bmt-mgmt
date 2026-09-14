-- calculate_session_costs lấy danh sách người chịu tiền từ
-- session_registrations, nên một dòng session_extra_charges của người chưa
-- đăng ký buổi không bao giờ tới được hóa đơn của ai. Không lỗi, không
-- cảnh báo -- khoản tiền đó đơn giản là biến mất.
-- SessionExtraCharges.vue ghi THẲNG vào bảng (không qua RPC nào), nên guard
-- phải nằm ở tầng bảng: một trigger BEFORE INSERT OR UPDATE.
BEGIN;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- Member A có đăng ký buổi: phụ thu ghi được và phải tới được hóa đơn.
INSERT INTO session_extra_charges (session_id, member_id, amount, note)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222',
        50000, 'Nước');

SELECT assert_eq(
  (SELECT total_extra_fee FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  50000::numeric, 'a charge for a registered member reaches the bill');

-- Admin (id 1111...) KHÔNG đăng ký buổi này. Phụ thu cho người đó phải bị
-- từ chối chứ không được ghi rồi rơi vào hư không.
DO $$
BEGIN
  BEGIN
    INSERT INTO session_extra_charges (session_id, member_id, amount, note)
    VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111',
            70000, 'Nước');
    RAISE EXCEPTION 'FAIL a charge for an unregistered member was written';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Thành viên này chưa đăng ký buổi%' THEN
      RAISE EXCEPTION 'FAIL unregistered charge was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   charge for an unregistered member rejected';
  END;
END $$;

SELECT assert_eq(
  (SELECT count(*)::int FROM session_extra_charges
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1, 'the rejected charge was not written');

-- UPDATE cũng phải bị chặn: dời một khoản hợp lệ sang người chưa đăng ký
-- làm tiền biến mất y hệt.
DO $$
BEGIN
  BEGIN
    UPDATE session_extra_charges
    SET member_id = '11111111-1111-1111-1111-111111111111'
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    RAISE EXCEPTION 'FAIL a charge was moved onto an unregistered member';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Thành viên này chưa đăng ký buổi%' THEN
      RAISE EXCEPTION 'FAIL the UPDATE was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   moving a charge onto an unregistered member rejected';
  END;
END $$;

SELECT assert_eq(
  (SELECT member_id FROM session_extra_charges
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  '22222222-2222-2222-2222-222222222222'::uuid, 'the rejected UPDATE changed nothing');

-- Hủy đăng ký rồi thì remove_member_from_session đã tự xóa phụ thu trước
-- khi xóa registration, nên guard không kẹt đường xóa người ra khỏi buổi.
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
SELECT remove_member_from_session(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222');

SELECT assert_eq(
  (SELECT count(*)::int FROM session_extra_charges
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0, 'removing a member still clears their charges');

RESET ROLE;
ROLLBACK;
