-- Function-level grants. Supabase exposes every function in the public
-- schema through /rest/v1/rpc, so anything that writes money must be
-- explicitly revoked from anon.
--
-- anon reaches EXECUTE on a newly created function through two independent
-- grants, and both must be revoked or the other one silently keeps anon in:
--   - PostgreSQL grants EXECUTE to PUBLIC on every function by default, and
--     anon is implicitly a member of PUBLIC, so `REVOKE ... FROM anon`
--     alone is a no-op — anon still gets in through PUBLIC.
--   - Supabase's own ALTER DEFAULT PRIVILEGES also grants EXECUTE directly
--     to anon (and authenticated, service_role) on every new function in
--     this schema, so `REVOKE ... FROM PUBLIC` alone is also a no-op here —
--     anon still gets in through its own direct grant.
-- A `DROP` followed by `CREATE` on any of these three functions re-applies
-- Supabase's default privileges from scratch and silently restores anon's
-- access; `CREATE OR REPLACE` preserves the existing ACL and is safe.
-- Whoever recreates one of these functions with DROP/CREATE must re-run
-- this file afterward.

REVOKE EXECUTE ON FUNCTION public.add_manual_payment(uuid, numeric, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.finalize_session(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.remove_member_from_session(uuid, uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.add_manual_payment(uuid, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_member_from_session(uuid, uuid) TO authenticated;

-- create_group_payment stays callable by anon: guests pay from the home page.
GRANT EXECUTE ON FUNCTION public.create_group_payment(uuid[]) TO anon, authenticated;

-- Read-only, safe for guests.
GRANT EXECUTE ON FUNCTION public.check_qr_status(text) TO anon, authenticated;

-- Trigger function; nothing should call it over the REST API.
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
