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

-- Input validation: dữ liệu thiếu hoặc vô lý phải bị từ chối tại RPC,
-- không được lặng lẽ biến thành 0 hay số âm trong tổng tiền.
--
-- Trước tiên: một payload hợp lệ vẫn phải ghi được bình thường -- các
-- guard mới không được false-positive trên dữ liệu tốt.
SELECT set_session_shuttle_usage(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '[{"type_id":"55555555-5555-5555-5555-555555555555","name":"Vina","tube_price":315000,"per_tube":12,"used":1}]'::jsonb);
-- 315000/12*1 = 26250
SELECT assert_eq(
  (SELECT shuttle_fee_total FROM sessions WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  26250::numeric, 'a valid payload still writes after the new guards');

-- Thiếu "used": SUM() sẽ lặng lẽ bỏ qua phần tử này (đóng góp 0) trong khi
-- nó vẫn được lưu trong shuttle_usage -- breakdown và tổng lệch nhau mà
-- không có tín hiệu gì.
DO $$
BEGIN
  BEGIN
    PERFORM set_session_shuttle_usage('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '[{"type_id":"55555555-5555-5555-5555-555555555555","name":"Vina","tube_price":315000,"per_tube":12}]'::jsonb);
    RAISE EXCEPTION 'FAIL usage missing "used" was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Thiếu số lượng ống cầu (used)%' THEN
      RAISE EXCEPTION 'FAIL missing "used" was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   missing "used" rejected';
  END;
END $$;

-- Thiếu "tube_price".
DO $$
BEGIN
  BEGIN
    PERFORM set_session_shuttle_usage('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '[{"type_id":"55555555-5555-5555-5555-555555555555","name":"Vina","per_tube":12,"used":1}]'::jsonb);
    RAISE EXCEPTION 'FAIL usage missing "tube_price" was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Thiếu giá ống cầu (tube_price)%' THEN
      RAISE EXCEPTION 'FAIL missing "tube_price" was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   missing "tube_price" rejected';
  END;
END $$;

-- Thiếu "per_tube".
DO $$
BEGIN
  BEGIN
    PERFORM set_session_shuttle_usage('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '[{"type_id":"55555555-5555-5555-5555-555555555555","name":"Vina","tube_price":315000,"used":1}]'::jsonb);
    RAISE EXCEPTION 'FAIL usage missing "per_tube" was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Thiếu số cầu mỗi ống (per_tube)%' THEN
      RAISE EXCEPTION 'FAIL missing "per_tube" was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   missing "per_tube" rejected';
  END;
END $$;

-- "used" âm: lặng lẽ trừ tiền khỏi tổng nếu không bị chặn.
DO $$
BEGIN
  BEGIN
    PERFORM set_session_shuttle_usage('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '[{"type_id":"55555555-5555-5555-5555-555555555555","name":"Vina","tube_price":315000,"per_tube":12,"used":-1}]'::jsonb);
    RAISE EXCEPTION 'FAIL negative "used" was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Số lượng ống cầu (used) không được âm%' THEN
      RAISE EXCEPTION 'FAIL negative "used" was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   negative "used" rejected';
  END;
END $$;

-- "per_tube" = 0: NULLIF trong công thức sẽ lặng lẽ biến phần tử này
-- thành 0 nếu không bị chặn trước.
DO $$
BEGIN
  BEGIN
    PERFORM set_session_shuttle_usage('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '[{"type_id":"55555555-5555-5555-5555-555555555555","name":"Vina","tube_price":315000,"per_tube":0,"used":1}]'::jsonb);
    RAISE EXCEPTION 'FAIL "per_tube" = 0 was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Số cầu mỗi ống (per_tube) phải lớn hơn 0%' THEN
      RAISE EXCEPTION 'FAIL "per_tube" = 0 was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   "per_tube" = 0 rejected';
  END;
END $$;

-- Làm tròn: tổng được làm tròn một lần, về nguyên đồng, sau khi cộng --
-- không làm tròn từng phần tử. 320000 không chia hết cho 12.
-- 320000 / 12 = 26666.666... ; used = 1 -> đóng góp 26666.666... ;
-- ROUND(26666.666...) = 26667.
SELECT set_session_shuttle_usage(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '[{"type_id":"88888888-8888-8888-8888-888888888888","name":"Carlton","tube_price":320000,"per_tube":12,"used":1}]'::jsonb);
SELECT assert_eq(
  (SELECT shuttle_fee_total FROM sessions WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  26667::numeric, 'total is rounded once to integer đồng, not per element');

-- Guard trạng thái: buổi không còn 'open' thì không sửa tiền cầu được
-- nữa, kể cả admin -- đúng thông điệp lỗi, không chỉ "có lỗi nào đó".
UPDATE sessions SET status = 'waiting_for_payment'
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

DO $$
BEGIN
  BEGIN
    PERFORM set_session_shuttle_usage('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '[]'::jsonb);
    RAISE EXCEPTION 'FAIL admin could edit shuttle usage on a non-open session';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Không thể sửa tiền cầu%' THEN
      RAISE EXCEPTION 'FAIL non-open session was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   non-open session rejected';
  END;
END $$;

-- Guard buổi không tồn tại: đúng thông điệp lỗi.
DO $$
BEGIN
  BEGIN
    PERFORM set_session_shuttle_usage('99999999-9999-9999-9999-999999999999', '[]'::jsonb);
    RAISE EXCEPTION 'FAIL a non-existent session was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Không tìm thấy buổi%' THEN
      RAISE EXCEPTION 'FAIL non-existent session was rejected for the wrong reason: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   non-existent session rejected';
  END;
END $$;

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
