BEGIN;

-- Setup: finalize as admin so we can test anon access after
SELECT login_as('authenticated', '11111111-1111-1111-1111-111111111111');
SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- Switch to anonymous visitor
SELECT login_as('anon');

-- Guests must still be able to read: /pay, polling and the home debt table.
SELECT assert_eq(
  (SELECT count(*)::int > 0 FROM session_costs_snapshot),
  true, 'anon can still read snapshots');

SELECT assert_eq(
  (SELECT count(*)::int > 0 FROM bank_config WHERE is_active),
  true, 'anon can still read the active bank config');

-- Guests must not be able to clear their own debt.
SELECT assert_denied($$UPDATE session_costs_snapshot SET paid_amount = final_amount$$, 'anon cannot mark snapshots paid');

SELECT assert_denied($$DELETE FROM session_payments$$, 'anon cannot delete payments');

-- Guests must not be able to redirect the QR to another bank account.
SELECT assert_denied($$UPDATE bank_config SET account_number = '9999999999'$$, 'anon cannot rewrite bank config');

SELECT assert_eq(
  (SELECT account_number FROM bank_config WHERE is_active),
  '10003392871', 'bank account number unchanged');

RESET ROLE;
ROLLBACK;
