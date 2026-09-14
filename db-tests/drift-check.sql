-- Read-only drift check between docs/sql-export/*.sql and production.
-- SELECT statements only — this is meant to run against production one day.
--
-- Run order matters: results are concatenated 1->8 into one file with no
-- headers, so the same eight queries must run in the same order on both
-- sides for `diff` to line up.

-- 1. tables and columns, WITH nullability. The type alone cannot see a
-- DROP NOT NULL, so the three money columns made NOT NULL on this branch
-- were invisible to the drift check until the marker below was added.
SELECT c.relname || ' | ' || string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod)
       || CASE WHEN a.attnotnull THEN ' NOT NULL' ELSE '' END, ', ' ORDER BY a.attnum) AS row
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE n.nspname = 'public' AND c.relkind = 'r'
GROUP BY c.relname ORDER BY c.relname;

-- 2. indexes
SELECT indexname AS row FROM pg_indexes
WHERE schemaname = 'public' ORDER BY indexname;

-- 3. policies
-- RLS qual/with_check expressions built from the admin-check subquery
-- ( EXISTS (SELECT 1 FROM members WHERE user_id = auth.uid() AND role =
-- 'admin') ) come back from pg_policies with embedded literal newlines
-- from Postgres's pretty-printer, which would break the one-row-per-line
-- format. Collapse all whitespace runs to a single space, then replace
-- the whole admin-check expression with the token ADMIN_CHECK — matching
-- the normalisation already applied to the production snapshot this is
-- diffed against.
SELECT tablename || ' | ' || policyname || ' | ' || cmd || ' | ' || roles::text
       || ' | ' || replace(
            regexp_replace(coalesce(qual, '-'), '\s+', ' ', 'g'),
            '(EXISTS ( SELECT 1 FROM members WHERE ((members.user_id = auth.uid()) AND (members.role = ''admin''::user_role))))',
            'ADMIN_CHECK')
       || ' | ' || replace(
            regexp_replace(coalesce(with_check, '-'), '\s+', ' ', 'g'),
            '(EXISTS ( SELECT 1 FROM members WHERE ((members.user_id = auth.uid()) AND (members.role = ''admin''::user_role))))',
            'ADMIN_CHECK')
       AS row
FROM pg_policies WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- 4. functions: name, args, security mode, search_path, and a body hash
-- Excludes objects that are pg_trgm-installed (not project code) and the
-- four test-bed-only helpers from db-tests/helpers.sql (assert_eq,
-- assert_money_eq, assert_denied, login_as), which exist only in the local
-- test bed.
SELECT p.proname || ' | ' || pg_get_function_identity_arguments(p.oid)
       || ' | secdef=' || p.prosecdef
       || ' | cfg=' || coalesce(array_to_string(p.proconfig, ','), '-')
       || ' | md5=' || md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g')) AS row
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname NOT LIKE 'gtrgm%' AND p.proname NOT LIKE 'gin_%'
  AND p.proname NOT IN ('set_limit','show_limit','show_trgm','similarity','similarity_dist',
                        'similarity_op','strict_word_similarity','strict_word_similarity_op',
                        'strict_word_similarity_dist_op','strict_word_similarity_commutator_op',
                        'strict_word_similarity_dist_commutator_op','word_similarity',
                        'word_similarity_op','word_similarity_dist_op',
                        'word_similarity_commutator_op','word_similarity_dist_commutator_op')
  AND p.proname NOT IN ('assert_eq','assert_denied','login_as','assert_money_eq')
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

-- 5. function grants: name, args, anon/authenticated has_function_privilege,
-- and the raw ACL. has_function_privilege alone can't tell a working
-- REVOKE from an inert one — anon reaches EXECUTE through two independent
-- grants (PostgreSQL's PUBLIC default and Supabase's ALTER DEFAULT
-- PRIVILEGES direct grant), and has_function_privilege returns true if
-- either one survives. The raw proacl is what actually proves both were
-- revoked. Same exclusions as query 4.
SELECT p.proname || ' | ' || pg_get_function_identity_arguments(p.oid)
       || ' | anon=' || has_function_privilege('anon', p.oid, 'execute')
       || ' | authenticated=' || has_function_privilege('authenticated', p.oid, 'execute')
       || ' | acl=' || coalesce(p.proacl::text, '-') AS row
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname NOT LIKE 'gtrgm%' AND p.proname NOT LIKE 'gin_%'
  AND p.proname NOT IN ('set_limit','show_limit','show_trgm','similarity','similarity_dist',
                        'similarity_op','strict_word_similarity','strict_word_similarity_op',
                        'strict_word_similarity_dist_op','strict_word_similarity_commutator_op',
                        'strict_word_similarity_dist_commutator_op','word_similarity',
                        'word_similarity_op','word_similarity_dist_op',
                        'word_similarity_commutator_op','word_similarity_dist_commutator_op')
  AND p.proname NOT IN ('assert_eq','assert_denied','login_as','assert_money_eq')
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

-- 6. triggers, non-internal, including the auth schema — on_auth_user_created
-- lives on auth.users, not public, and query 4 alone missed it before.
SELECT n.nspname || '.' || c.relname || ' | ' || t.tgname || ' | ' || p.proname AS row
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE NOT t.tgisinternal AND n.nspname IN ('public', 'auth')
ORDER BY 1;

-- 7. views, whitespace-collapsed to one row per view. pg_get_viewdef
-- pretty-prints with embedded newlines, which would break the
-- one-row-per-line format. This is the query that was missing entirely:
-- view_session_summary holds the SECOND copy of the pricing decision (the
-- first is in calculate_session_costs), and a production still running the
-- superseded per-interval expression diffed clean before this existed.
SELECT c.relname || ' | ' || regexp_replace(pg_get_viewdef(c.oid), '\s+', ' ', 'g') AS row
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'v'
ORDER BY c.relname;

-- 8. constraints (CHECK, PRIMARY KEY, UNIQUE, FOREIGN KEY, EXCLUDE).
-- session_court_bookings_time_order_check and
-- session_court_bookings_court_name_not_blank are both new this branch and
-- neither appeared in any drift query. Joined through pg_class rather than
-- casting conrelid::regclass, so the output does not depend on the reader's
-- search_path.
SELECT cl.relname || ' | ' || con.conname || ' | '
       || regexp_replace(pg_get_constraintdef(con.oid), '\s+', ' ', 'g') AS row
FROM pg_constraint con
JOIN pg_class cl ON cl.oid = con.conrelid
JOIN pg_namespace n ON n.oid = cl.relnamespace
WHERE n.nspname = 'public'
ORDER BY cl.relname, con.conname;
