BEGIN;

-- Setup: finalize as admin so this call doesn't trip the very guard this
-- file exists to verify (finalize_session gains an admin check below; the
-- setup call must already present as admin, not as the default no-claim
-- caller).
SELECT login_as('authenticated', '11111111-1111-1111-1111-111111111111');
SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- As an anonymous visitor: every money-writing RPC must refuse. Anon is
-- also REVOKEd EXECUTE in 09_grants.sql, so the block may come from the
-- grant system (insufficient_privilege) or from the in-function admin
-- check (raise_exception) — either is an acceptable "blocked".
SELECT login_as('anon');

DO $$
BEGIN
  BEGIN
    PERFORM add_manual_payment(
      (SELECT id FROM session_costs_snapshot LIMIT 1), 1000, 'hack');
    RAISE EXCEPTION 'FAIL anon could call add_manual_payment';
  EXCEPTION WHEN insufficient_privilege OR raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    RAISE NOTICE 'ok   anon blocked from add_manual_payment';
  END;
END $$;

DO $$
BEGIN
  BEGIN
    PERFORM finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    RAISE EXCEPTION 'FAIL anon could call finalize_session';
  EXCEPTION WHEN insufficient_privilege OR raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    RAISE NOTICE 'ok   anon blocked from finalize_session';
  END;
END $$;

DO $$
BEGIN
  BEGIN
    PERFORM remove_member_from_session(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '33333333-3333-3333-3333-333333333333');
    RAISE EXCEPTION 'FAIL anon could remove a member';
  EXCEPTION WHEN insufficient_privilege OR raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    RAISE NOTICE 'ok   anon blocked from remove_member_from_session';
  END;
END $$;

-- Prove the REVOKE actually fires at the grant layer and isn't just
-- riding on the in-function admin check above: anon must be refused
-- specifically with insufficient_privilege (42501, "permission denied for
-- function ..."). add_manual_payment gets EXECUTE from two independent
-- sources by default (PostgreSQL's PUBLIC grant, and Supabase's own
-- default-privileges grant direct to anon) — 09_grants.sql must revoke
-- both, or anon still gets in through whichever one was missed and this
-- call falls through to raise_exception (the admin check) instead.
DO $$
BEGIN
  BEGIN
    PERFORM add_manual_payment(
      (SELECT id FROM session_costs_snapshot LIMIT 1), 1000, 'hack');
    RAISE EXCEPTION 'FAIL anon executed add_manual_payment (REVOKE did not fire)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'ok   anon refused by privilege on add_manual_payment (REVOKE ... FROM PUBLIC, anon is effective)';
    WHEN raise_exception THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      RAISE EXCEPTION 'FAIL anon was stopped only by the admin check, not by REVOKE — the grant-level REVOKE on add_manual_payment is inert';
  END;
END $$;

-- The mirror image: create_group_payment is deliberately NOT revoked from
-- anon (guests pay from the public home page), so anon must still reach
-- its function body. Any exception raised from inside the body is fine —
-- insufficient_privilege is not, since that would mean anon's grant on it
-- got stripped too.
DO $$
BEGIN
  BEGIN
    PERFORM create_group_payment(ARRAY['00000000-0000-0000-0000-000000000000'::uuid]);
    RAISE EXCEPTION 'FAIL create_group_payment succeeded with a bogus snapshot id (test bug, not a real pass)';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE EXCEPTION 'FAIL anon lost EXECUTE on create_group_payment — the public group-payment flow would be broken';
    WHEN OTHERS THEN
      IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
      RAISE NOTICE 'ok   anon still reaches create_group_payment''s body (%), the public-payment flow is intact', SQLERRM;
  END;
END $$;

RESET ROLE;

-- remove_member_from_session's own status check only allows removal from
-- an 'open' session; finalize_session above moved this session to
-- 'waiting_for_payment'. Put it back so the admin guard below is the only
-- thing that can stop the non-admin call — otherwise the status check
-- would raise first, and the test could not tell guard from status check.
UPDATE sessions SET status = 'open'
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- As a signed-in non-admin member: also refused, for ALL THREE functions.
-- authenticated holds EXECUTE (09_grants.sql), so only the in-function
-- admin check can stop this — a guard that only stopped anon would leave
-- every logged-in member free to write money rows.
SELECT login_as('authenticated', '22222222-2222-2222-2222-222222222222');

DO $$
BEGIN
  BEGIN
    PERFORM add_manual_payment(
      (SELECT id FROM session_costs_snapshot LIMIT 1), 1000, 'hack');
    RAISE EXCEPTION 'FAIL non-admin could call add_manual_payment';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    RAISE NOTICE 'ok   non-admin blocked from add_manual_payment';
  END;
END $$;

DO $$
BEGIN
  BEGIN
    PERFORM finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    RAISE EXCEPTION 'FAIL non-admin could call finalize_session';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    RAISE NOTICE 'ok   non-admin blocked from finalize_session';
  END;
END $$;

-- The session is 'open' (reset above), so the only thing that can stop
-- this call is the admin guard itself — assert on the guard's own message
-- rather than accepting any raise_exception, or a guard-less function
-- would pass this test by tripping some other check instead.
DO $$
BEGIN
  BEGIN
    PERFORM remove_member_from_session(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '33333333-3333-3333-3333-333333333333');
    RAISE EXCEPTION 'FAIL non-admin could remove a member';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'Chỉ admin%' THEN
      RAISE EXCEPTION 'FAIL non-admin was blocked by the status check, not the admin guard: %', SQLERRM;
    END IF;
    RAISE NOTICE 'ok   non-admin blocked from remove_member_from_session by the admin guard';
  END;
END $$;

RESET ROLE;

-- As admin: all three still work.
SELECT login_as('authenticated', '11111111-1111-1111-1111-111111111111');

SELECT add_manual_payment(
  (SELECT id FROM session_costs_snapshot
    WHERE member_id = '33333333-3333-3333-3333-333333333333'), 50000, 'cash');

SELECT assert_eq(
  (SELECT paid_amount FROM session_costs_snapshot
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  50000::numeric, 'admin can record a cash payment');

-- Carry-over from Task 2: finalize_session's ON CONFLICT DO UPDATE picks
-- status via `paid_amount >= EXCLUDED.final_amount THEN 'paid'`. That
-- branch is only reachable through finalize_session itself when a member
-- has paid their bill in full and gets re-finalized with no price change
-- (a `>` typo here would silently regress to 'partial' and go undetected
-- by 01_finalize_status.test.sql, which never re-finalizes a fully paid
-- member at an unchanged price). Member B's final_amount is 140000; top
-- the 50000 already paid up to exactly that.
SELECT add_manual_payment(
  (SELECT id FROM session_costs_snapshot
    WHERE member_id = '33333333-3333-3333-3333-333333333333'), 90000, 'cash exact');

SELECT assert_eq(
  (SELECT status::text FROM session_costs_snapshot
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  'paid', 'B is paid in full before re-finalize');

SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

SELECT assert_eq(
  (SELECT status::text FROM session_costs_snapshot
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  'paid', 'B stays paid after re-finalize at an unchanged price');

SELECT assert_eq(
  (SELECT paid_amount FROM session_costs_snapshot
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  140000::numeric, 'B paid_amount untouched by re-finalize');

-- Positive counterpart: admin CAN remove a member from an open session.
-- Run last, using member A (not B) so it does not disturb the fixture
-- state the boundary assertions above depend on.
UPDATE sessions SET status = 'open'
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

SELECT remove_member_from_session(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '22222222-2222-2222-2222-222222222222');

SELECT assert_eq(
  (SELECT count(*)::int FROM session_registrations
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      AND member_id = '22222222-2222-2222-2222-222222222222'),
  0, 'admin can remove a member from an open session');

RESET ROLE;
ROLLBACK;
