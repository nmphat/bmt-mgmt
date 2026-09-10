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

-- ── Nhánh cũ, price_per_hour khác 0: khóa phép nhân trong ELSE arm ──
-- 280000/140000 ở trên không đi qua (v_price_per_hour/2.0)*active_court_count vì
-- price_per_hour = 0 triệt tiêu nó — addon và shuttle gánh hết, không assertion
-- nào khóa nhánh giờ khác 0. 11 buổi thật trên production có price_per_hour
-- 100k-140k, không buổi nào NULL: đây là nhánh mà 11 buổi đó đi qua mỗi lần
-- tính tiền, và nếu ELSE arm bị hỏng (nhân sai, xóa phép nhân) thì hai
-- assertion phía trên vẫn xanh vì chúng nhân với 0.
UPDATE sessions SET price_per_hour = 100000
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- v_total_court_units = 2+1 = 3, v_ghost_count = 0.
-- interval 0 (active_court_count=2, real_present=2: A và B):
--   court = ((100000/2)*2 + 300000*2/3) / 2 = (100000+200000)/2 = 150000/người
--   shuttle = (120000*2/3)/2 = 40000/người
-- interval 1 (active_court_count=1, real_present=1: chỉ A):
--   court (A) = ((100000/2)*1 + 300000*1/3) / 1 = (50000+100000)/1 = 150000
--   shuttle (A) = (120000*1/3)/1 = 40000
--   B vắng interval 1 -> 0
-- A = (150000+150000) + (40000+40000) = 300000 + 80000 = 380000
-- B = 150000 + 40000 = 190000
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  380000::numeric, 'legacy session, nonzero hourly rate: member A');

SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  190000::numeric, 'legacy session, nonzero hourly rate: member B');

-- Trả price_per_hour về 0 để phần còn lại của file thấy đúng trạng thái đã viết cho nó.
UPDATE sessions SET price_per_hour = 0
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- ── Nhánh mới: cùng buổi đó, nay có giá sân thật ──
-- Tắt shuttle trước để cô lập phần tiền sân; addon (300k) giữ nguyên một nhịp
-- nữa để khóa tính cộng dồn (Option C additive) trước khi bị tắt luôn ở dưới.
UPDATE sessions SET shuttle_fee_total = 0
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time, price_per_hour) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 1',
   '2026-09-01 11:00:00+00', '2026-09-01 11:30:00+00', 120000),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 1',
   '2026-09-01 11:30:00+00', '2026-09-01 12:00:00+00', 130000);

SELECT refresh_interval_courts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- Sau refresh chỉ còn Sân 1 phủ mỗi interval -> active_court_count = 1 ở cả
-- hai interval, v_total_court_units = 1+1 = 2.
-- court_cost: interval 0 = 120000*0.5 = 60000; interval 1 = 130000*0.5 = 65000.

-- ── Cộng dồn: addon (300000, chưa tắt) phải CỘNG vào court_cost, không bị nuốt ──
-- interval 0: (60000 + 300000*1/2) / 2 = (60000+150000)/2 = 105000/người (A, B cùng mặt)
-- interval 1: (65000 + 300000*1/2) / 1 = (65000+150000)/1 = 215000 (chỉ A)
-- A = 105000 + 215000 = 320000
-- B = 105000
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  320000::numeric, 'priced session, addon still on: member A gets booking cost plus addon share');

SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  105000::numeric, 'priced session, addon still on: member B gets booking cost plus addon share');

-- Bỏ court_fee_addon để cô lập phần tiền sân mới cho các assertion tiếp theo.
UPDATE sessions SET court_fee_addon = 0
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

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
