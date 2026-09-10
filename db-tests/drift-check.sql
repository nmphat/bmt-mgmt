-- Read-only drift check between docs/sql-export/*.sql and production.
-- SELECT statements only — this is meant to run against production one day.
--
-- Run order matters: results are concatenated 1->6 into one file with no
-- headers, so the same six queries must run in the same order on both
-- sides for `diff` to line up.

-- 1. tables and columns
SELECT c.relname || ' | ' || string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ', ' ORDER BY a.attnum) AS row
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
-- three test-bed-only helpers from db-tests/helpers.sql (assert_eq,
-- assert_denied, login_as), which exist only in the local test bed.
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
  AND p.proname NOT IN ('assert_eq','assert_denied','login_as')
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
  AND p.proname NOT IN ('assert_eq','assert_denied','login_as')
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
