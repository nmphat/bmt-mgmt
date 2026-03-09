-- Enable RLS and recreate policies
ALTER TABLE public.bank_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Access" ON public.bank_config; CREATE POLICY "Public Access" ON public.bank_config AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Public read access" ON public.bank_config; CREATE POLICY "Public read access" ON public.bank_config AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS bank_config_public_read ON public.bank_config; CREATE POLICY bank_config_public_read ON public.bank_config AS PERMISSIVE FOR SELECT TO public USING (true);
ALTER TABLE public.group_payment_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public create group request" ON public.group_payment_requests; CREATE POLICY "Public create group request" ON public.group_payment_requests AS PERMISSIVE FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "Public read access" ON public.group_payment_requests; CREATE POLICY "Public read access" ON public.group_payment_requests AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "Public read group request" ON public.group_payment_requests; CREATE POLICY "Public read group request" ON public.group_payment_requests AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
ALTER TABLE public.interval_presence ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anon read presence" ON public.interval_presence; CREATE POLICY "Anon read presence" ON public.interval_presence AS PERMISSIVE FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "Auth users full access presence" ON public.interval_presence; CREATE POLICY "Auth users full access presence" ON public.interval_presence AS PERMISSIVE FOR ALL TO authenticated USING (true);
DROP POLICY IF EXISTS "Public read access" ON public.interval_presence; CREATE POLICY "Public read access" ON public.interval_presence AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
ALTER TABLE public.members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Auth users full access members" ON public.members; CREATE POLICY "Auth users full access members" ON public.members AS PERMISSIVE FOR ALL TO authenticated USING (true);
DROP POLICY IF EXISTS "Public read access" ON public.members; CREATE POLICY "Public read access" ON public.members AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
ALTER TABLE public.session_costs_snapshot ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Access" ON public.session_costs_snapshot; CREATE POLICY "Public Access" ON public.session_costs_snapshot AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Public read access" ON public.session_costs_snapshot; CREATE POLICY "Public read access" ON public.session_costs_snapshot AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
ALTER TABLE public.session_court_bookings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin manage bookings" ON public.session_court_bookings; CREATE POLICY "Admin manage bookings" ON public.session_court_bookings AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM members
  WHERE ((members.user_id = auth.uid()) AND (members.role = 'admin'::user_role)))));
DROP POLICY IF EXISTS "Public read bookings" ON public.session_court_bookings; CREATE POLICY "Public read bookings" ON public.session_court_bookings AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
ALTER TABLE public.session_extra_charges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin manage charges" ON public.session_extra_charges; CREATE POLICY "Admin manage charges" ON public.session_extra_charges AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM members
  WHERE ((members.user_id = auth.uid()) AND (members.role = 'admin'::user_role)))));
DROP POLICY IF EXISTS "Public read charges" ON public.session_extra_charges; CREATE POLICY "Public read charges" ON public.session_extra_charges AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
ALTER TABLE public.session_intervals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anon read intervals" ON public.session_intervals; CREATE POLICY "Anon read intervals" ON public.session_intervals AS PERMISSIVE FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "Auth users full access intervals" ON public.session_intervals; CREATE POLICY "Auth users full access intervals" ON public.session_intervals AS PERMISSIVE FOR ALL TO authenticated USING (true);
DROP POLICY IF EXISTS "Public read access" ON public.session_intervals; CREATE POLICY "Public read access" ON public.session_intervals AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
ALTER TABLE public.session_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Access" ON public.session_payments; CREATE POLICY "Public Access" ON public.session_payments AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Public read access" ON public.session_payments; CREATE POLICY "Public read access" ON public.session_payments AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
ALTER TABLE public.session_registrations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin delete registration" ON public.session_registrations; CREATE POLICY "Admin delete registration" ON public.session_registrations AS PERMISSIVE FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM members
  WHERE ((members.user_id = auth.uid()) AND (members.role = 'admin'::user_role)))));
DROP POLICY IF EXISTS "Admin insert registration" ON public.session_registrations; CREATE POLICY "Admin insert registration" ON public.session_registrations AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM members
  WHERE ((members.user_id = auth.uid()) AND (members.role = 'admin'::user_role)))));
DROP POLICY IF EXISTS "Admin update registration" ON public.session_registrations; CREATE POLICY "Admin update registration" ON public.session_registrations AS PERMISSIVE FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM members
  WHERE ((members.user_id = auth.uid()) AND (members.role = 'admin'::user_role)))));
DROP POLICY IF EXISTS "Auth users full access registrations" ON public.session_registrations; CREATE POLICY "Auth users full access registrations" ON public.session_registrations AS PERMISSIVE FOR ALL TO authenticated USING (true);
DROP POLICY IF EXISTS "Public read access" ON public.session_registrations; CREATE POLICY "Public read access" ON public.session_registrations AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anon read sessions" ON public.sessions; CREATE POLICY "Anon read sessions" ON public.sessions AS PERMISSIVE FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "Auth users full access sessions" ON public.sessions; CREATE POLICY "Auth users full access sessions" ON public.sessions AS PERMISSIVE FOR ALL TO authenticated USING (true);
DROP POLICY IF EXISTS "Public read access" ON public.sessions; CREATE POLICY "Public read access" ON public.sessions AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
