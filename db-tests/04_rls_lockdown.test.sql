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

-- Guests must not be able to call the soft-delete/gc family either. These
-- three carry no admin guard in the body -- their only defence beyond RLS
-- is the REVOKE in 09_grants.sql -- so assert the specific SQLSTATE
-- (insufficient_privilege), not merely "some exception was raised", or a
-- REVOKE that never fired would look identical to one that did.
DO $$
BEGIN
  BEGIN
    PERFORM soft_delete_cancelled_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    RAISE EXCEPTION 'FAIL anon executed soft_delete_cancelled_session (REVOKE did not fire)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'ok   anon refused by privilege on soft_delete_cancelled_session';
    WHEN OTHERS THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      RAISE EXCEPTION 'FAIL anon reached soft_delete_cancelled_session''s body (%) — the REVOKE is inert', SQLERRM;
  END;
END $$;

DO $$
BEGIN
  BEGIN
    PERFORM soft_delete_cancelled_sessions_bulk(ARRAY['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid]);
    RAISE EXCEPTION 'FAIL anon executed soft_delete_cancelled_sessions_bulk (REVOKE did not fire)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'ok   anon refused by privilege on soft_delete_cancelled_sessions_bulk';
    WHEN OTHERS THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      RAISE EXCEPTION 'FAIL anon reached soft_delete_cancelled_sessions_bulk''s body (%) — the REVOKE is inert', SQLERRM;
  END;
END $$;

DO $$
BEGIN
  BEGIN
    PERFORM gc_soft_deleted_sessions();
    RAISE EXCEPTION 'FAIL anon executed gc_soft_deleted_sessions (REVOKE did not fire)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'ok   anon refused by privilege on gc_soft_deleted_sessions';
    WHEN OTHERS THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      RAISE EXCEPTION 'FAIL anon reached gc_soft_deleted_sessions''s body (%) — the REVOKE is inert', SQLERRM;
  END;
END $$;

RESET ROLE;
ROLLBACK;
