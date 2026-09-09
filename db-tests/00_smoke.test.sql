BEGIN;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

SELECT assert_eq((SELECT count(*)::int FROM members), 3, 'members seeded');
SELECT assert_eq((SELECT count(*)::int FROM session_intervals), 2, 'intervals seeded');

-- Worked example from docs/context/02-business-logic.md, minus the ghost member:
--   interval 1: real_present = 2, ghost = 0  -> court (300k*2/3)/2 = 100000 each
--   interval 2: real_present = 1, ghost = 0  -> court (300k*1/3)/1 = 100000
--   shuttle    1: (120k*2/3)/2 = 40000 each; 2: (120k*1/3)/1 = 40000
-- A = 100000+100000 court + 40000+40000 shuttle = 280000
-- B = 100000        court + 40000        shuttle = 140000
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  280000::numeric, 'member A final_total');

SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  140000::numeric, 'member B final_total');

-- RLS negative/positive control: proves the bed can tell the difference
-- between "blocked by RLS" and "blocked for the wrong reason" (e.g. a
-- typo'd table name, or the assertion silently running as superuser).
--
-- Negative: anon has only a SELECT policy on members at this point in the
-- plan, so an UPDATE as anon must affect 0 rows.
SELECT login_as('anon');
SELECT assert_denied($$UPDATE members SET display_name = 'hacked'$$, 'anon cannot rename members');

-- Positive: the same UPDATE, as the superuser connection, must actually
-- work and hit all 3 seeded rows — otherwise the negative control above
-- could be passing because the UPDATE itself is broken, not because RLS
-- blocked it.
RESET ROLE;
WITH updated AS (
  UPDATE members SET display_name = 'hacked' RETURNING 1
)
SELECT assert_eq(count(*)::int, 3, 'superuser can rename members (positive control)') FROM updated;

-- Rolled back below, so none of this persists — display_name is restored.
ROLLBACK;
