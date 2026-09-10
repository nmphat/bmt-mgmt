BEGIN;

INSERT INTO shuttle_types (id, name, tube_price, per_tube) VALUES
  ('55555555-5555-5555-5555-555555555555', 'Vina',   315000, 12),
  ('66666666-6666-6666-6666-666666666666', 'Victor', 360000, 12);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

SELECT set_session_shuttle_usage(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '[{"type_id":"55555555-5555-5555-5555-555555555555","name":"Vina","tube_price":315000,"per_tube":12,"used":3},
    {"type_id":"66666666-6666-6666-6666-666666666666","name":"Victor","tube_price":360000,"per_tube":12,"used":2}]'::jsonb);

-- 315000/12*3 = 78750 ; 360000/12*2 = 60000 ; tổng = 138750
SELECT assert_eq(
  (SELECT shuttle_fee_total FROM sessions WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  138750::numeric, 'shuttle total derived from tube price and count');

SELECT assert_eq(
  (SELECT jsonb_array_length(shuttle_usage) FROM sessions
    WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2, 'usage breakdown stored alongside the total');

-- Snapshot: đổi giá trong danh mục không được đổi tiền của buổi.
UPDATE shuttle_types SET tube_price = 999000
WHERE id = '55555555-5555-5555-5555-555555555555';

SELECT assert_eq(
  (SELECT shuttle_fee_total FROM sessions WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  138750::numeric, 'catalog price change does not touch a recorded session');

-- Danh sách rỗng đưa tổng về 0.
SELECT set_session_shuttle_usage('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '[]'::jsonb);
SELECT assert_eq(
  (SELECT shuttle_fee_total FROM sessions WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::numeric, 'clearing usage zeroes the total');

RESET ROLE;

-- Admin guard: không phải admin thì set_session_shuttle_usage phải từ chối,
-- đúng thông điệp của guard (không phải một lý do khác trùng hợp cũng chặn được).
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

DO $$
BEGIN
  BEGIN
    PERFORM set_session_shuttle_usage('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '[]'::jsonb);
    RAISE EXCEPTION 'FAIL non-admin could set shuttle usage';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Chỉ admin%' THEN
      RAISE EXCEPTION 'FAIL non-admin was blocked by the wrong guard: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   non-admin blocked from set_session_shuttle_usage';
  END;
END $$;

RESET ROLE;

-- Grant-level revoke: anon phải không chạm được vào thân hàm luôn --
-- lỗi phải là insufficient_privilege (từ REVOKE), không phải raise_exception
-- (từ admin guard bên trong thân hàm). Nếu REVOKE không có tác dụng, anon
-- sẽ lọt vào thân hàm và bị admin guard chặn thay -- test này phải phân
-- biệt được hai trường hợp đó.
SELECT login_as('anon');

DO $$
BEGIN
  BEGIN
    PERFORM set_session_shuttle_usage('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '[]'::jsonb);
    RAISE EXCEPTION 'FAIL anon executed set_session_shuttle_usage (REVOKE did not fire)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'ok   anon refused by privilege on set_session_shuttle_usage';
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      RAISE EXCEPTION 'FAIL anon was stopped only by the admin check, not by REVOKE — the grant-level REVOKE on set_session_shuttle_usage is inert';
  END;
END $$;

RESET ROLE;

-- Read policy: khách (anon) không đọc được danh mục -- danh mục là cấu
-- hình admin, chỉ màn hình cài đặt và trình soạn buổi mới cần, cả hai đều
-- sau đăng nhập. authenticated đọc được đầy đủ hai loại đã seed.
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claim.sub = '';
SELECT assert_eq(
  (SELECT count(*)::int FROM shuttle_types), 0, 'anon cannot read the shuttle type catalog');
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
SELECT assert_eq(
  (SELECT count(*)::int FROM shuttle_types), 2, 'authenticated member can read the shuttle type catalog');

-- Write policy: một authenticated không phải admin thì không được sửa
-- danh mục.
--
-- INSERT không có tập "trước" để USING lọc; WITH CHECK thất bại thì
-- Postgres báo lỗi thật (42501, insufficient_privilege), không phải
-- lặng lẽ trả về 0 dòng -- nên bắt đúng SQLSTATE bằng DO block ở đây,
-- không dùng assert_denied (nó sẽ làm cả script vỡ vì lỗi thoát ra
-- ngoài EXECUTE).
DO $$
BEGIN
  BEGIN
    INSERT INTO shuttle_types (name, tube_price, per_tube) VALUES ('Yonex', 340000, 12);
    RAISE EXCEPTION 'FAIL non-admin could insert a shuttle type';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'ok   non-admin cannot insert a shuttle type';
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      RAISE EXCEPTION 'FAIL non-admin insert was refused for the wrong reason (%), not RLS', SQLERRM;
  END;
END $$;

-- UPDATE: USING lọc trước khi ghi, nên bị chặn thì ra 0 dòng, đúng chỗ
-- assert_denied là công cụ đúng.
SELECT assert_denied(
  $$UPDATE shuttle_types SET tube_price = 1 WHERE id = '55555555-5555-5555-5555-555555555555'$$,
  'non-admin cannot update a shuttle type');

RESET ROLE;

-- Nhưng admin thì sửa được.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

INSERT INTO shuttle_types (id, name, tube_price, per_tube)
VALUES ('77777777-7777-7777-7777-777777777777', 'Yonex', 340000, 12);

SELECT assert_eq(
  (SELECT count(*)::int FROM shuttle_types WHERE id = '77777777-7777-7777-7777-777777777777'),
  1, 'admin can insert a shuttle type');

UPDATE shuttle_types SET tube_price = 345000
WHERE id = '77777777-7777-7777-7777-777777777777';

SELECT assert_eq(
  (SELECT tube_price FROM shuttle_types WHERE id = '77777777-7777-7777-7777-777777777777'),
  345000::numeric, 'admin can update a shuttle type');

RESET ROLE;

-- Khách cũng không ghi được (không chỉ không đọc được).
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claim.sub = '';
SELECT assert_denied(
  $$UPDATE shuttle_types SET tube_price = 1 WHERE id = '55555555-5555-5555-5555-555555555555'$$,
  'anon cannot edit the catalog');
RESET ROLE;

ROLLBACK;
