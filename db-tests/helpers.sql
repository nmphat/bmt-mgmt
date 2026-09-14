-- RULE: this test bed connects as `postgres`, a superuser — and a
-- superuser bypasses row-level security unconditionally, regardless of
-- role grants and regardless of FORCE ROW LEVEL SECURITY. Any test
-- asserting that a role CANNOT do something MUST go through login_as()
-- to switch into that role, then assert_denied() to run the statement —
-- never a bare statement under the default superuser connection. A test
-- that skips this will pass whether or not the RLS policy actually works.

-- Supabase roles referenced by 08_rls.sql
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;

-- Supabase auth schema + auth.uid() stub.
-- Tests impersonate a user with:  SET request.jwt.claim.sub = '<uuid>';
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY);

-- Byte-for-byte the definition Supabase runs in production. Verified against
-- pg_get_functiondef on project bufpmpehugzysvmbjlub on 2026-09-10.
-- The second branch is the one PostgREST actually uses; the first is legacy.
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE AS $$
  select
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;

-- Assertion helper. Raises, so ON_ERROR_STOP=1 turns a failed assert into
-- a non-zero exit code from psql.
CREATE OR REPLACE FUNCTION assert_eq(actual anyelement, expected anyelement, label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF actual IS DISTINCT FROM expected THEN
    RAISE EXCEPTION 'FAIL % — expected %, got %', label, expected, actual;
  END IF;
  RAISE NOTICE 'ok   %', label;
END;
$$;

-- Supabase grants PostgREST roles table + function access by default.
-- Reproduce that here so RLS, not missing grants, is what the tests measure.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Role-impersonation + guarded-denial helpers (see the RULE at the top of
-- this file). Created after the ALTER DEFAULT PRIVILEGES above so they
-- pick up the same EXECUTE grant to anon/authenticated/service_role as
-- every other function created from here on.

-- Switch the current transaction into p_role, with p_uid as its JWT sub
-- claim (empty string, i.e. anonymous, when p_uid is NULL). SET LOCAL
-- semantics: unwinds automatically at COMMIT/ROLLBACK.
CREATE OR REPLACE FUNCTION login_as(p_role text, p_uid uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- Set request.jwt.claim.sub for backward compatibility with existing tests
  PERFORM set_config('request.jwt.claim.sub', COALESCE(p_uid::text, ''), true);
  -- Set request.jwt.claims as JSON, matching the production path PostgREST uses
  PERFORM set_config('request.jwt.claims',
                     case when p_uid is null then ''
                          else json_build_object('sub', p_uid::text, 'role', p_role)::text end,
                     true);
  EXECUTE format('SET LOCAL ROLE %I', p_role);
END;
$$;

-- Assert that p_sql, run as the CURRENT role, affects 0 rows. Refuses to
-- run at all if the current role is a superuser, because a superuser
-- bypasses RLS and the assertion would prove nothing. Use after login_as().
CREATE OR REPLACE FUNCTION assert_denied(p_sql text, p_label text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_is_superuser boolean;
  v_rowcount     int;
BEGIN
  SELECT rolsuper INTO v_is_superuser FROM pg_roles WHERE rolname = current_user;

  IF v_is_superuser THEN
    RAISE EXCEPTION 'assert_denied % — current role "%" is a superuser, RLS is bypassed, this assertion proves nothing. Call login_as() first.', p_label, current_user;
  END IF;

  EXECUTE p_sql;
  GET DIAGNOSTICS v_rowcount = ROW_COUNT;

  IF v_rowcount <> 0 THEN
    RAISE EXCEPTION 'FAIL % — expected 0 rows affected, got %', p_label, v_rowcount;
  END IF;

  RAISE NOTICE 'ok   %', p_label;
END;
$$;

-- Money assertion with a tolerance. The engine-vs-view reconciliation
-- compares two numeric expressions that add the same VND in a different
-- order, so an addon that does not divide evenly comes back as
-- 99999.999999999999 against 100000.000000000000 — a 1e-12 drift that is
-- not money. Tiền là số nguyên VND và final_total còn được CEIL lên bội
-- số 1000, nên sai lệch THẬT nhỏ nhất có thể xảy ra là 1 đồng: epsilon
-- 0.01 đồng nằm giữa hai thang đó, cao hơn nhiễu numeric hàng tỉ lần và
-- vẫn thấp hơn 1 đồng 100 lần.
CREATE OR REPLACE FUNCTION assert_money_eq(actual numeric, expected numeric, label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF actual IS NULL OR expected IS NULL OR abs(actual - expected) >= 0.01 THEN
    RAISE EXCEPTION 'FAIL % — expected %, got % (drift %)',
      label, expected, actual, coalesce((actual - expected)::text, 'NULL');
  END IF;
  RAISE NOTICE 'ok   %', label;
END;
$$;
