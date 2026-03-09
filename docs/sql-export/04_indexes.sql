CREATE INDEX idx_group_code ON public.group_payment_requests USING btree (group_code);
CREATE INDEX idx_group_fingerprint ON public.group_payment_requests USING btree (fingerprint);
CREATE INDEX idx_members_user_id ON public.members USING btree (user_id);
CREATE INDEX idx_sessions_deleted_at ON public.sessions USING btree (deleted_at);
CREATE INDEX idx_sessions_status_deleted_at ON public.sessions USING btree (status, deleted_at);
CREATE INDEX idx_intervals_session ON public.session_intervals USING btree (session_id);
CREATE INDEX idx_registrations_session ON public.session_registrations USING btree (session_id);
CREATE INDEX idx_presence_interval_member ON public.interval_presence USING btree (interval_id, member_id);
