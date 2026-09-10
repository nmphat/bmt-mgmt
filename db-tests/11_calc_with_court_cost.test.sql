BEGIN;

-- ── Nhánh cũ: buổi không có giá sân, tiền phải y hệt trước khi sửa ──
-- Fixture: price_per_hour = 0, court_fee_addon = 300k, shuttle = 120k
-- A có mặt cả 2 interval, B có mặt interval 0. Không có ghost.
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  280000::numeric, 'legacy session: member A unchanged');

SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  140000::numeric, 'legacy session: member B unchanged');

-- ── Nhánh mới: cùng buổi đó, nay có giá sân thật ──
-- Bỏ court_fee_addon để cô lập phần tiền sân mới.
UPDATE sessions SET court_fee_addon = 0, shuttle_fee_total = 0
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time, price_per_hour) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 1',
   '2026-09-01 11:00:00+00', '2026-09-01 11:30:00+00', 120000),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 1',
   '2026-09-01 11:30:00+00', '2026-09-01 12:00:00+00', 130000);

SELECT refresh_interval_courts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- court_cost: interval 0 = 120000*0.5 = 60000; interval 1 = 130000*0.5 = 65000
-- interval 0: A và B cùng có mặt, ghost = 0 -> mỗi người 60000/2 = 30000
-- interval 1: chỉ A          -> A thêm 65000/1 = 65000
-- A = 30000 + 65000 = 95000
-- B = 30000
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  95000::numeric, 'priced session: member A pays for both intervals');

SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  30000::numeric, 'priced session: member B pays for one interval');

-- Tổng thu phải bằng tổng tiền sân thực tế, không thất thoát.
SELECT assert_eq(
  (SELECT sum(total_court_fee) FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  125000::numeric, 'court money adds up to what the courts cost');

-- ── Ghost vẫn chịu tiền sân ──
INSERT INTO members (id, display_name, role, is_active)
VALUES ('44444444-4444-4444-4444-444444444444', 'Ghost', 'member', true);
INSERT INTO session_registrations (session_id, member_id)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '44444444-4444-4444-4444-444444444444');

-- interval 0: real = 2, ghost = 1 -> mẫu số 3 -> 60000/3 = 20000 mỗi suất
-- interval 1: real = 1, ghost = 1 -> mẫu số 2 -> 65000/2 = 32500 mỗi suất
-- Ghost tính cả hai interval: 20000 + 32500 = 52500 -> làm tròn 53000
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '44444444-4444-4444-4444-444444444444'),
  53000::numeric, 'ghost still pays court fee under the new model');

ROLLBACK;
