-- Auth users (admin only; the other two members are not linked)
INSERT INTO auth.users (id) VALUES ('11111111-1111-1111-1111-111111111111');

INSERT INTO members (id, user_id, display_name, role, is_active) VALUES
  ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Admin', 'admin', true),
  ('22222222-2222-2222-2222-222222222222', NULL, 'Member A', 'member', true),
  ('33333333-3333-3333-3333-333333333333', NULL, 'Member B', 'member', true);

-- Old-style session: price_per_hour = 0, all court money in court_fee_addon
INSERT INTO sessions (id, title, start_time, end_time, price_per_hour, court_fee_addon, shuttle_fee_total, status)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Fixture session',
        '2026-09-01 11:00:00+00', '2026-09-01 12:00:00+00', 0, 300000, 120000, 'open');

-- Two 30-minute intervals, 2 courts then 1 court
INSERT INTO session_intervals (id, session_id, start_time, end_time, idx, active_court_count) VALUES
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '2026-09-01 11:00:00+00', '2026-09-01 11:30:00+00', 0, 2),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '2026-09-01 11:30:00+00', '2026-09-01 12:00:00+00', 1, 1);

-- A and B registered; A present in both intervals, B present in the first only
INSERT INTO session_registrations (session_id, member_id) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333');

INSERT INTO interval_presence (interval_id, member_id, is_present) VALUES
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', '22222222-2222-2222-2222-222222222222', true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', '22222222-2222-2222-2222-222222222222', true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', '33333333-3333-3333-3333-333333333333', true);

INSERT INTO bank_config (bank_id, account_number, account_name, template, is_active)
VALUES ('TPB', '10003392871', 'CLB CAU LONG BMT', 'compact2', true);
