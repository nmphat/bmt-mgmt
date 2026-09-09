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

ROLLBACK;
