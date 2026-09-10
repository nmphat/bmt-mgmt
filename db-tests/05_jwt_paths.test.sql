BEGIN;

-- Test that auth.uid() correctly reads from both JWT claim paths:
-- 1. request.jwt.claim.sub (legacy path)
-- 2. request.jwt.claims JSON blob (production path used by PostgREST)

-- Setup: finalize session as admin using the standard login_as path
SELECT login_as('authenticated', '11111111-1111-1111-1111-111111111111');
SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- Test 1: auth.uid() returns correct UUID when only request.jwt.claim.sub is set
RESET ROLE;
SET LOCAL request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
SET LOCAL request.jwt.claims = '';

SELECT assert_eq(
  auth.uid(),
  '22222222-2222-2222-2222-222222222222'::uuid,
  'auth.uid() reads from request.jwt.claim.sub (legacy path)');

-- Test 2: auth.uid() returns correct UUID when only request.jwt.claims JSON is set
RESET ROLE;
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

SELECT assert_eq(
  auth.uid(),
  '33333333-3333-3333-3333-333333333333'::uuid,
  'auth.uid() reads from request.jwt.claims JSON (production path)');

-- Test 3: auth.uid() returns NULL when both are empty
RESET ROLE;
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL request.jwt.claims = '';

SELECT assert_eq(
  auth.uid(),
  NULL::uuid,
  'auth.uid() returns NULL when both paths are empty');

-- Test 4: auth.uid() prefers request.jwt.claim.sub when both are set (coalesce priority)
RESET ROLE;
SET LOCAL request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
SET LOCAL request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

SELECT assert_eq(
  auth.uid(),
  '22222222-2222-2222-2222-222222222222'::uuid,
  'auth.uid() prioritizes request.jwt.claim.sub when both paths are set');

-- Test 5: Admin guard in finalize_session accepts admin via JSON claims path only
-- This verifies that the inline admin guard uses auth.uid() correctly.
RESET ROLE;
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
SET LOCAL ROLE authenticated;

-- This should succeed because auth.uid() extracts admin UUID from JSON claims
SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

SELECT assert_eq(
  (SELECT count(*)::int FROM session_costs_snapshot WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2,
  'admin can finalize session when providing auth via JSON claims path');

RESET ROLE;
ROLLBACK;
