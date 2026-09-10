-- Function-level grants. Supabase exposes every function in the public
-- schema through /rest/v1/rpc, so anything that writes money must be
-- explicitly revoked from anon.

REVOKE EXECUTE ON FUNCTION public.add_manual_payment(uuid, numeric, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.finalize_session(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.remove_member_from_session(uuid, uuid) FROM anon;

GRANT EXECUTE ON FUNCTION public.add_manual_payment(uuid, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_member_from_session(uuid, uuid) TO authenticated;

-- create_group_payment stays callable by anon: guests pay from the home page.
GRANT EXECUTE ON FUNCTION public.create_group_payment(uuid[]) TO anon, authenticated;

-- Read-only, safe for guests.
GRANT EXECUTE ON FUNCTION public.check_qr_status(text) TO anon, authenticated;
