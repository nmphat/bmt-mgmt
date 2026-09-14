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

-- Danh sách buổi phải khớp engine ở CẢ BA hình dạng buổi. Hình dạng 1:
-- buổi thuần addon (price_per_hour = 0, không có booking nào có giá).
-- So sánh với sum(total_court_fee) chứ không phải sum(final_total):
-- final_total đã cộng tiền cầu và làm tròn lên bội số 1000 cho từng người,
-- còn total_court_fee là tiền sân chưa làm tròn -- đúng thứ view đang nói.
SELECT assert_money_eq(
  (SELECT total_court_cost FROM view_session_summary WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  (SELECT sum(total_court_fee) FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  'addon-only session: list total agrees with the engine');

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

-- Danh sách buổi (view_session_summary.total_court_cost) phải khớp với
-- engine tính tiền. Nếu view quay về công thức cũ
-- (active_court_count * price_per_hour / 2) thì mọi buổi tính theo giá sân
-- -- vốn có price_per_hour = 0 -- sẽ hiện 0 đồng trong danh sách trong khi
-- thành viên vẫn bị tính đủ tiền.
SELECT assert_money_eq(
  (SELECT total_court_cost FROM view_session_summary WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  (SELECT sum(total_court_fee) FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  'per-court session: list total agrees with the engine');

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

-- ── CHỐT SỐ TIỀN CHO HÌNH DẠNG CỦA 43 BUỔI TRÊN PRODUCTION ──
-- Đây là hình dạng thật của toàn bộ dữ liệu cũ: price_per_hour > 0, booking
-- có tồn tại nhưng price_per_hour = 0 (47/47 dòng trên production), tiền sân
-- nằm ở court_fee_addon, và hai thành viên có số buổi có mặt KHÁC nhau (nếu
-- bằng nhau thì mọi cách chia đều cho ra cùng một con số và assertion không
-- chứng minh được gì). Cờ v_has_priced_booking phải là FALSE ở đây, nên cả
-- buổi đi theo công thức giờ cũ và số tiền phải y hệt trước khi sửa.
DELETE FROM session_registrations
WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  AND member_id = '44444444-4444-4444-4444-444444444444';
DELETE FROM session_court_bookings WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

UPDATE sessions
SET price_per_hour = 100000, court_fee_addon = 300000, shuttle_fee_total = 120000
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- Sân 1 phủ cả buổi, Sân 2 chỉ nửa đầu -> active_court_count 2 rồi 1, đúng
-- như fixture ban đầu; cả hai đều price_per_hour = 0 nên court_cost = 0.
INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time, price_per_hour) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 1',
   '2026-09-01 11:00:00+00', '2026-09-01 12:00:00+00', 0),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 2',
   '2026-09-01 11:00:00+00', '2026-09-01 11:30:00+00', 0);

SELECT refresh_interval_courts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

SELECT assert_eq(
  (SELECT sum(court_cost) FROM session_intervals
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::numeric, 'legacy shape: every booking priced 0 leaves court_cost at 0');

SELECT assert_eq(
  (SELECT sum(active_court_count)::int FROM session_intervals
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  3, 'legacy shape: court-units are 2 + 1 as on production');

-- v_total_court_units = 3, ghost = 0.
-- interval 0 (2 sân, A và B): court ((100000/2)*2 + 300000*2/3)/2 = 150000/người
--                             shuttle (120000*2/3)/2 = 40000/người
-- interval 1 (1 sân, chỉ A):  court ((100000/2)*1 + 300000*1/3)/1 = 150000
--                             shuttle (120000*1/3)/1 = 40000
-- A = 300000 + 80000 = 380000 ; B = 150000 + 40000 = 190000
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  380000::numeric, 'production-shaped session: member A still pays exactly 380000');

SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  190000::numeric, 'production-shaped session: member B still pays exactly 190000');

SELECT assert_money_eq(
  (SELECT total_court_cost FROM view_session_summary WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  (SELECT sum(total_court_fee) FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  'production-shaped session: list total agrees with the engine');

-- Cùng hình dạng đó nhưng price_per_hour = 0: buổi thuần addon có booking
-- 0 đồng. Cả hai vế chỉ còn lại addon.
UPDATE sessions SET price_per_hour = 0 WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

SELECT assert_eq(
  (SELECT total_court_cost FROM view_session_summary WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  300000::numeric, 'addon-only session with zero-priced bookings: list shows just the addon');

SELECT assert_money_eq(
  (SELECT total_court_cost FROM view_session_summary WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  (SELECT sum(total_court_fee) FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  'addon-only session with zero-priced bookings: list total agrees with the engine');

UPDATE sessions SET price_per_hour = 100000 WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- ── Buổi TRỘN: có giá sân thật ở khung này, sân 0 đồng ở khung kia ──
-- Trước đây nhánh được chọn theo từng interval (court_cost > 0), nên khung
-- có sân 0 đồng lặng lẽ quay về công thức giờ cũ và bịa thêm 100000/2 đồng
-- cho một khung mà câu lạc bộ không trả đồng nào. Nay cờ được chốt cho cả
-- buổi: đã có giá sân thì khung 0 đồng đóng góp đúng 0 đồng.
DELETE FROM session_court_bookings WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

UPDATE sessions SET court_fee_addon = 0, shuttle_fee_total = 0
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
-- price_per_hour = 100000 vẫn còn nguyên: đó chính là cái bẫy.

INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time, price_per_hour) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 1',
   '2026-09-01 11:00:00+00', '2026-09-01 11:30:00+00', 120000),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 2',
   '2026-09-01 11:30:00+00', '2026-09-01 12:00:00+00', 0);

SELECT refresh_interval_courts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

SELECT assert_eq(
  (SELECT court_cost FROM session_intervals WHERE idx = 1
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::numeric, 'mixed session: the free slot really costs nothing');

-- Tiền sân thật của buổi = 120000 * 0.5 = 60000. Không được thành 110000.
SELECT assert_eq(
  (SELECT sum(total_court_fee) FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  60000::numeric, 'mixed session: total charged equals what the courts really cost');

-- interval 0 (60000, A và B cùng mặt) -> 30000 mỗi người
-- interval 1 (0, chỉ A)               -> A thêm 0
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  30000::numeric, 'mixed session: member A is not billed the legacy hourly rate for the free slot');

SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  30000::numeric, 'mixed session: member B pays her share of the one priced slot');

-- view_session_summary mang BẢN SAO của đúng biểu thức đó. Nếu nó vẫn chọn
-- nhánh theo từng interval trong khi engine đã chốt theo buổi, danh sách sẽ
-- báo 110000 cho một buổi mà hóa đơn thật là 60000 -- lệch đúng ở những buổi
-- trộn giá mà D2 sinh ra để sửa.
SELECT assert_eq(
  (SELECT total_court_cost FROM view_session_summary WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  60000::numeric, 'mixed session: list total is the real court spend, not 110000');

SELECT assert_money_eq(
  (SELECT total_court_cost FROM view_session_summary WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  (SELECT sum(total_court_fee) FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  'mixed session: list total agrees with the engine');


-- ── Interval KHÔNG có ai điểm danh: tiền sân của khung đó vẫn phải có người trả ──
-- Hình dạng thật và dựng được từ UI: buổi 11:00-13:00, một sân 120000/h, hai
-- người chỉ ở lại tiếng đầu rồi admin bỏ tick hai ô cuối của lưới điểm danh.
-- Câu lạc bộ vẫn trả đủ 240000 tiền sân. Trước đây engine chỉ chia 120000:
-- hai interval cuối không có ai điểm danh nên cả biểu thức tiền sân trả 0 và
-- 120000 đồng không vào hóa đơn của ai, trong khi danh sách buổi vẫn hiện
-- 240000 -- hai con số trên cùng một màn hình admin không khớp nhau và không
-- có gì đối chiếu chúng.
INSERT INTO sessions (id, title, start_time, end_time, price_per_hour, court_fee_addon, shuttle_fee_total, status)
VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Empty interval session',
        '2026-09-02 11:00:00+00', '2026-09-02 13:00:00+00', 0, 0, 0, 'open');

INSERT INTO session_intervals (session_id, start_time, end_time, idx, active_court_count)
SELECT 'cccccccc-cccc-cccc-cccc-cccccccccccc',
       '2026-09-02 11:00:00+00'::timestamptz + (g * INTERVAL '30 minutes'),
       '2026-09-02 11:00:00+00'::timestamptz + ((g + 1) * INTERVAL '30 minutes'),
       g, 0
FROM generate_series(0, 3) g;

INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time, price_per_hour)
VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Sân 1',
        '2026-09-02 11:00:00+00', '2026-09-02 13:00:00+00', 120000);

SELECT refresh_interval_courts('cccccccc-cccc-cccc-cccc-cccccccccccc');

INSERT INTO session_registrations (session_id, member_id) VALUES
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '22222222-2222-2222-2222-222222222222'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '33333333-3333-3333-3333-333333333333');

-- Đúng thứ togglePresence ghi: có mặt ở idx 0,1 và KHÔNG có mặt ở idx 2,3.
INSERT INTO interval_presence (interval_id, member_id, is_present)
SELECT i.id, m.member_id, (i.idx < 2)
FROM session_intervals i
CROSS JOIN (VALUES ('22222222-2222-2222-2222-222222222222'::uuid),
                   ('33333333-3333-3333-3333-333333333333'::uuid)) m(member_id)
WHERE i.session_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

SELECT assert_eq(
  (SELECT sum(court_cost) FROM session_intervals
    WHERE session_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  240000::numeric, 'empty interval: the club really paid for all four intervals');

SELECT assert_eq(
  (SELECT count(*)::int FROM session_intervals i
    WHERE i.session_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
      AND NOT EXISTS (SELECT 1 FROM interval_presence p
                      WHERE p.interval_id = i.id AND p.is_present)),
  2, 'empty interval: two intervals really have nobody present');

-- Mỗi interval 60000, chia đều cho 2 người đã đăng ký ở khung không ai có
-- mặt và cho 2 người có mặt ở khung có người -> 30000/người/interval.
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('cccccccc-cccc-cccc-cccc-cccccccccccc')
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  120000::numeric, 'empty interval: member A pays for the empty intervals too');

SELECT assert_eq(
  (SELECT sum(total_court_fee) FROM calculate_session_costs('cccccccc-cccc-cccc-cccc-cccccccccccc')),
  240000::numeric, 'empty interval: every VND of court money is billed to somebody');

SELECT assert_money_eq(
  (SELECT total_court_cost FROM view_session_summary WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  (SELECT sum(total_court_fee) FROM calculate_session_costs('cccccccc-cccc-cccc-cccc-cccccccccccc')),
  'empty interval: list total agrees with the engine');

-- ── Cùng hình dạng đó nhưng có thêm một ghost ──
-- Ghost đã trả tiền sân ở MỌI interval theo luật cũ. Khung không ai có mặt
-- chia cho mọi người đã đăng ký, nên ghost vẫn chỉ chịu ĐÚNG MỘT suất của
-- khung đó, không bị tính hai lần; tổng vẫn phải đúng bằng tiền sân thật.
INSERT INTO members (id, display_name, role, is_active)
VALUES ('55555555-5555-5555-5555-555555555555', 'Ghost 2', 'member', true);
INSERT INTO session_registrations (session_id, member_id)
VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', '55555555-5555-5555-5555-555555555555');

-- 4 interval x 60000, mỗi khung chia 3 suất -> 20000/suất, ai cũng chịu cả 4
-- khung: 80000/người.
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('cccccccc-cccc-cccc-cccc-cccccccccccc')
    WHERE member_id = '55555555-5555-5555-5555-555555555555'),
  80000::numeric, 'empty interval with a ghost: the ghost pays exactly one share per interval');

SELECT assert_eq(
  (SELECT sum(total_court_fee) FROM calculate_session_costs('cccccccc-cccc-cccc-cccc-cccccccccccc')),
  240000::numeric, 'empty interval with a ghost: court money still adds up exactly');

SELECT assert_money_eq(
  (SELECT total_court_cost FROM view_session_summary WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  (SELECT sum(total_court_fee) FROM calculate_session_costs('cccccccc-cccc-cccc-cccc-cccccccccccc')),
  'empty interval with a ghost: list total agrees with the engine');

-- Cùng hình dạng đó trên buổi TÍNH THEO GIỜ CŨ (không booking nào có giá):
-- danh sách buổi cộng (active_court_count * price_per_hour / 2) trên MỌI
-- interval, nên engine cũng phải chia đủ trên mọi interval.
UPDATE session_court_bookings SET price_per_hour = 0
WHERE session_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
UPDATE sessions SET price_per_hour = 100000, court_fee_addon = 90000
WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
SELECT refresh_interval_courts('cccccccc-cccc-cccc-cccc-cccccccccccc');

SELECT assert_money_eq(
  (SELECT total_court_cost FROM view_session_summary WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  (SELECT sum(total_court_fee) FROM calculate_session_costs('cccccccc-cccc-cccc-cccc-cccccccccccc')),
  'empty interval, legacy hourly session: list total agrees with the engine');



-- ── Tiền cầu của một interval không ai có mặt ──
-- Ghost KHÔNG trả tiền cầu (luật đã chốt), nên trọng số của tiền cầu phải
-- chạy trên RIÊNG những interval CÓ người. Trước đây nó chia cho
-- v_total_court_units tính trên MỌI interval, nên phần của khung không ai
-- có mặt không có ai nhận và rơi ra ngoài mọi hóa đơn -- lặng lẽ y như tiền
-- sân, chỉ khác là danh sách buổi cũng không hiện ra được.
INSERT INTO sessions (id, title, start_time, end_time, price_per_hour, court_fee_addon, shuttle_fee_total, status)
VALUES ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'Empty interval shuttle',
        '2026-09-04 11:00:00+00', '2026-09-04 13:00:00+00', 0, 0, 120000, 'open');

INSERT INTO session_intervals (session_id, start_time, end_time, idx, active_court_count)
SELECT 'dddddddd-dddd-dddd-dddd-dddddddddddd',
       '2026-09-04 11:00:00+00'::timestamptz + (g * INTERVAL '30 minutes'),
       '2026-09-04 11:00:00+00'::timestamptz + ((g + 1) * INTERVAL '30 minutes'),
       g, 0
FROM generate_series(0, 3) g;

INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time, price_per_hour)
VALUES ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'Sân 1',
        '2026-09-04 11:00:00+00', '2026-09-04 13:00:00+00', 120000);

SELECT refresh_interval_courts('dddddddd-dddd-dddd-dddd-dddddddddddd');

INSERT INTO session_registrations (session_id, member_id) VALUES
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '22222222-2222-2222-2222-222222222222'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '33333333-3333-3333-3333-333333333333');

INSERT INTO interval_presence (interval_id, member_id, is_present)
SELECT i.id, m.member_id, (i.idx < 2)
FROM session_intervals i
CROSS JOIN (VALUES ('22222222-2222-2222-2222-222222222222'::uuid),
                   ('33333333-3333-3333-3333-333333333333'::uuid)) m(member_id)
WHERE i.session_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

-- Hai khung có người gánh toàn bộ 120000: (120000 * 1/2) / 2 = 30000 mỗi
-- người mỗi khung -> 60000/người.
SELECT assert_eq(
  (SELECT sum(total_shuttle_fee) FROM calculate_session_costs('dddddddd-dddd-dddd-dddd-dddddddddddd')),
  120000::numeric, 'empty interval: the whole shuttle fee is split among the people who were there');

SELECT assert_eq(
  (SELECT total_shuttle_fee FROM calculate_session_costs('dddddddd-dddd-dddd-dddd-dddddddddddd')
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  60000::numeric, 'empty interval: member A carries half the shuttle fee');

-- Ghost vẫn không trả một đồng tiền cầu nào.
INSERT INTO session_registrations (session_id, member_id)
VALUES ('dddddddd-dddd-dddd-dddd-dddddddddddd', '55555555-5555-5555-5555-555555555555');

SELECT assert_eq(
  (SELECT total_shuttle_fee FROM calculate_session_costs('dddddddd-dddd-dddd-dddd-dddddddddddd')
    WHERE member_id = '55555555-5555-5555-5555-555555555555'),
  0::numeric, 'empty interval: the ghost still pays no shuttle fee');

SELECT assert_eq(
  (SELECT sum(total_shuttle_fee) FROM calculate_session_costs('dddddddd-dddd-dddd-dddd-dddddddddddd')),
  120000::numeric, 'empty interval with a ghost: the shuttle fee is still fully split');

-- Không có overlap sân nào -> nhánh fallback của tiền cầu cũng phải đếm
-- riêng những interval có người.
DELETE FROM session_court_bookings WHERE session_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
SELECT refresh_interval_courts('dddddddd-dddd-dddd-dddd-dddddddddddd');

SELECT assert_eq(
  (SELECT sum(total_shuttle_fee) FROM calculate_session_costs('dddddddd-dddd-dddd-dddd-dddddddddddd')),
  120000::numeric, 'no court overlap: the shuttle fallback still splits the whole fee');


ROLLBACK;
