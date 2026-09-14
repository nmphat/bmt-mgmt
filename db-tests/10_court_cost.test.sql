BEGIN;

-- anon cannot call refresh_interval_courts (SECURITY DEFINER, revoked from anon)
SELECT login_as('anon', NULL);
DO $$
BEGIN
  BEGIN
    PERFORM refresh_interval_courts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    RAISE EXCEPTION 'FAIL anon executed refresh_interval_courts (REVOKE did not fire)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'ok   anon refused by privilege on refresh_interval_courts';
    WHEN OTHERS THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      RAISE EXCEPTION 'FAIL anon reached refresh_interval_courts body (%) — the REVOKE is inert', SQLERRM;
  END;
END $$;
SELECT login_as('authenticated', '11111111-1111-1111-1111-111111111111');

-- Sân 1 chia hai khung giá, sân 2 một khung phủ cả buổi.
INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time, price_per_hour) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 1',
   '2026-09-01 11:00:00+00', '2026-09-01 11:30:00+00', 120000),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 1',
   '2026-09-01 11:30:00+00', '2026-09-01 12:00:00+00', 130000),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 2',
   '2026-09-01 11:00:00+00', '2026-09-01 12:00:00+00', 135000);

SELECT refresh_interval_courts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- Interval 0 (11:00-11:30): Sân 1 @120k + Sân 2 @135k, mỗi sân nửa giờ
--   = 120000*0.5 + 135000*0.5 = 60000 + 67500 = 127500
SELECT assert_eq(
  (SELECT court_cost FROM session_intervals WHERE idx = 0
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  127500::numeric, 'interval 0 court_cost');

-- Interval 1 (11:30-12:00): Sân 1 @130k + Sân 2 @135k
--   = 130000*0.5 + 135000*0.5 = 65000 + 67500 = 132500
SELECT assert_eq(
  (SELECT court_cost FROM session_intervals WHERE idx = 1
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  132500::numeric, 'interval 1 court_cost');

-- active_court_count phải giữ nguyên hành vi cũ: đếm booking phủ interval.
SELECT assert_eq(
  (SELECT active_court_count FROM session_intervals WHERE idx = 0
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2, 'interval 0 still counts two courts');

-- Booking không có giá (buổi cũ) phải cho court_cost = 0, không phải NULL.
DELETE FROM session_court_bookings
WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 1',
   '2026-09-01 11:00:00+00', '2026-09-01 12:00:00+00');

SELECT refresh_interval_courts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

SELECT assert_eq(
  (SELECT court_cost FROM session_intervals WHERE idx = 0
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::numeric, 'legacy booking leaves court_cost at zero');

ROLLBACK;
