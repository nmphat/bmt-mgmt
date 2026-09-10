BEGIN;

SELECT login_as('authenticated', '11111111-1111-1111-1111-111111111111');
SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

SELECT login_as('anon');

-- A guest creates a group code for both members.
SELECT create_group_payment(ARRAY(SELECT id FROM session_costs_snapshot ORDER BY id));

SELECT assert_eq(
  (SELECT total_amount FROM group_payment_requests),
  (SELECT sum(final_amount - paid_amount) FROM session_costs_snapshot),
  'group total matches the debt at creation');

RESET ROLE;

-- One member pays. The stored total must refresh when the code is reused.
UPDATE session_costs_snapshot
SET paid_amount = final_amount, status = 'paid'
WHERE member_id = '22222222-2222-2222-2222-222222222222';

SELECT login_as('anon');
SELECT create_group_payment(ARRAY(SELECT id FROM session_costs_snapshot ORDER BY id));

SELECT assert_eq(
  (SELECT count(*)::int FROM group_payment_requests),
  1, 'reuse does not create a second row');

SELECT assert_eq(
  (SELECT total_amount FROM group_payment_requests),
  (SELECT sum(final_amount - paid_amount) FROM session_costs_snapshot),
  'reused group total refreshed to the remaining debt');

-- check_qr_status reads that column, so it must agree.
SELECT assert_eq(
  ((SELECT check_qr_status(group_code) FROM group_payment_requests)->>'total')::numeric,
  (SELECT sum(final_amount - paid_amount) FROM session_costs_snapshot),
  'check_qr_status reports the refreshed total');

RESET ROLE;
ROLLBACK;
