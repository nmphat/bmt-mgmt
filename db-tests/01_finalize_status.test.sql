BEGIN;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- Finalize once, then let member A pay in full.
SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

UPDATE session_costs_snapshot
SET paid_amount = final_amount, status = 'paid'
WHERE member_id = '22222222-2222-2222-2222-222222222222';

SELECT assert_eq(
  (SELECT status::text FROM session_costs_snapshot
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  'paid', 'A is paid before the price change');

-- Admin raises the shuttle fee and re-finalizes.
UPDATE sessions SET shuttle_fee_total = 240000
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- A now owes more than they paid, so the row must drop back to partial.
SELECT assert_eq(
  (SELECT status::text FROM session_costs_snapshot
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  'partial', 'A falls back to partial after the price rise');

-- And the debt must be visible again.
SELECT assert_eq(
  (SELECT count(*)::int FROM view_member_debt_summary
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  1, 'A reappears in the debt summary');

-- B never paid, so B stays pending.
SELECT assert_eq(
  (SELECT status::text FROM session_costs_snapshot
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  'pending', 'B stays pending');

ROLLBACK;
